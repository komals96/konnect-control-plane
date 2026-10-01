#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common/fetch_konnect_token.sh
source "${SCRIPT_DIR}/../common/fetch_konnect_token.sh"
###############################################################################
# Global Configuration
###############################################################################

KONNECT_API_BASE="${KONNECT_API_BASE:-https://global.api.konghq.com/v3}"
PLATFORM_OPS_SECRET_NAME=""
PLATFORM_OPS_TOKEN_BASE_NAME="konnect-platform-ops-cp-admin-sat"
DEFAULT_TTL_DAYS="${TOKEN_TTL_DAYS:-365}"

###############################################################################
# Logging / Error Handling
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    printf '%b%s%b\n' "${BLUE}" "$*" "${NC}"
}

success() {
    printf '%b[SUCCESS] %s%b\n' "${GREEN}" "$*" "${NC}"
}

debug() {
    printf '%b[DEBUG] %s%b\n' "${YELLOW}" "$*" "${NC}" >&2
}

fail() {
    printf '%b[ERROR] %s%b\n' "${RED}" "$*" "${NC}" >&2
    exit 1
}

###############################################################################
# Usage
###############################################################################

usage() {
cat <<'EOF'

Usage:
API Ops      : ./token-rotation.sh <env> api-ops <ttl-days> <cp-type>
Platform Ops : ./token-rotation.sh platform-ops [ttl-days]

Examples:
./token-rotation.sh dev api-ops 365 dc
./token-rotation.sh platform-ops 365

Allowed:
env      : dev | uat | ppd | prd
cp-type  : onprem | gcloud
ttl-days : 1-365 (default: 365)

EOF
}

###############################################################################
# Prerequisites
###############################################################################

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        fail "Required command not found: $1"
}

validate_prerequisites() {
    require_command gcloud
    require_command jq
    require_command curl
    require_command date
}

###############################################################################
# Argument Normalization
###############################################################################

normalize_environment() {
    local env_name="${1,,}"
    case "${env_name}" in
        dev|uat|ppd) printf '%s' "${env_name}" ;;
        prd|prod) printf '%s' "prd" ;;
        *) fail "Invalid environment '${env_name}'. Allowed values: dev, uat, ppd, prd (prod is accepted as an alias)" ;;
    esac
}

normalize_cp_type() {
    local cp_type="${1,,}"
    case "${cp_type}" in
        onprem|gcloud) printf '%s' "${cp_type}" ;;
        *) fail "Invalid cp-type '${cp_type}'. Allowed values: onprem, gcloud" ;;
    esac
}

normalize_token_type() {
    local token_type="${1,,}"
    case "${token_type}" in
        api-ops) printf '%s' "${token_type}" ;;
        *) fail "Invalid token type '${token_type}'. Expected: api-ops" ;;
    esac
}

# Argument Validation
###############################################################################

validate_api_environment() {
    normalize_environment "$1" >/dev/null
}

validate_cp_type() {
    normalize_cp_type "$1" >/dev/null
}

validate_ttl() {
    local ttl="$1"

    [[ "${ttl}" =~ ^[0-9]+$ ]] ||
        fail "TTL must be a positive integer. Received: ${ttl}"

    (( ttl > 0 )) ||
        fail "TTL must be greater than 0"

    if (( ttl > 365 )); then
        fail "TTL cannot exceed 365 days because Konnect system account tokens have a maximum duration of 12 months"
    fi
}

###############################################################################
# Set GCP Project Based on Environment
###############################################################################

set_gcp_project() {
    ENV_NAME="$(normalize_environment "${ENV_NAME}")"

    case "${ENV_NAME}" in
        dev|uat) GCP_PROJECT="us-nprd-itg-api-kong-01" ;;
        ppd)     GCP_PROJECT="us-pprd-itg-api-kong-01" ;;
        prd)     GCP_PROJECT="us-prod-itg-api-kong-01" ;;
        *)       fail "Unable to determine GCP project for environment: ${ENV_NAME}" ;;
    esac

    export ENV_NAME GCP_PROJECT
}

###############################################################################
# Secret Name Functions
###############################################################################

build_api_ops_secret_name() {
    local env_name cp_type project_prefix
    env_name="$(normalize_environment "$1")"
    cp_type="$(normalize_cp_type "$2")"

    case "${env_name}" in
        dev|uat) project_prefix="us-nprd" ;;
        ppd)     project_prefix="us-pprd" ;;
        prd)     project_prefix="us-prod" ;;
        *)       fail "Unable to determine secret prefix for environment: ${env_name}" ;;
    esac

    echo "${project_prefix}-itg-api-kong-konnect-${cp_type}-cp-info-${env_name}"
}

get_secret_name() {

    local token_type="${TOKEN_TYPE:-}"
    local environment="${ENVIRONMENT:-}"
    local cp_type="${CP_TYPE:-}"

    if [[ "${token_type}" == "platform-ops" ]]; then
        echo "${PLATFORM_OPS_SECRET_NAME}"
        return
    fi

    if [[ -z "${environment}" ]]; then
        fail "Environment is empty while resolving API Ops secret name"
    fi

    if [[ -z "${cp_type}" ]]; then
        fail "Control plane type is empty while resolving API Ops secret name"
    fi

    build_api_ops_secret_name "${environment}" "${cp_type}"
}

build_platform_ops_secret_name() {
    local env_name project_prefix
    env_name="$(normalize_environment "$1")"

    # Platform Ops authentication always comes from PROD.
    [[ "${env_name}" == "prd" ]] ||
        fail "Platform Ops authentication secret must be resolved from PROD. Received environment: ${env_name}"

    project_prefix="us-prod"
    echo "${project_prefix}-itg-api-kong-konnect-platform-ops-sat-info"
}

###############################################################################
# Token Name Functions
###############################################################################

build_api_ops_token_name() {
    echo "${ENV_NAME}-${CP_TYPE}-api-ops-deployer-sat"
}

build_platform_ops_timestamped_token_name() {
    local timestamp

    timestamp="$(date -u '+%Y%m%d%H%M%S')"

    echo "${PLATFORM_OPS_TOKEN_BASE_NAME}-${timestamp}"
}

build_platform_ops_final_token_name() {
    echo "${PLATFORM_OPS_TOKEN_BASE_NAME}"
}

###############################################################################
# Date Functions
###############################################################################

get_expiry_date() {
    date -u -d "+${TTL_DAYS} days" '+%Y-%m-%dT%H:%M:%SZ'
}

###############################################################################
# GCP Secret Manager
###############################################################################

fetch_secret() {
    local secret_name="$1"
    local project="$2"

    debug "----------------------------------------------"
    debug "GCP Secret Manager processing"
    debug "----------------------------------------------"
    debug "Requested Secret : ${secret_name}"
    debug "GCP Project      : ${project}"

    gcloud secrets versions access latest \
        --secret="${secret_name}" \
        --project="${project}"
}

add_secret_version() {
    local secret_name="$1"
    local secret_json="$2"
    local project="$3"

    printf '%s' "${secret_json}" |
        gcloud secrets versions add "${secret_name}" \
            --project="${project}" \
            --data-file=- \
            >/dev/null
}

###############################################################################
# Secret Validation
###############################################################################

validate_secret_json() {
    local secret_json="$1"
    local secret_name="$2"

    echo "${secret_json}" | jq empty >/dev/null 2>&1 ||
        fail "Secret '${secret_name}' does not contain valid JSON"
}

###############################################################################
# Konnect API
###############################################################################

create_konnect_token() {
    local auth_token="$1"
    local system_account_id="$2"
    local token_name="$3"
    local expires_at="$4"

    local response_file
    local http_status

    response_file="$(mktemp)"

    http_status="$(
        curl -sS \
            -o "${response_file}" \
            -w "%{http_code}" \
            --request POST \
            "${KONNECT_API_BASE}/system-accounts/${system_account_id}/access-tokens" \
            --header "Authorization: Bearer ${auth_token}" \
            --header "Content-Type: application/json" \
            --header "Accept: application/json" \
            --data "$(jq -n \
                --arg name "${token_name}" \
                --arg expires_at "${expires_at}" \
                '{
                    name: $name,
                    expires_at: $expires_at
                }'
            )"
    )"

    if [[ "${http_status}" -lt 200 || "${http_status}" -ge 300 ]]; then
        echo "Konnect create token API failed." >&2
        echo "HTTP Status: ${http_status}" >&2
        echo "Response:" >&2
        cat "${response_file}" >&2
        rm -f -- "${response_file}"
        return 1
    fi

    local new_token_id
    local new_token

    new_token_id="$(jq -r '.id // empty' "${response_file}")"
    new_token="$(jq -r '.token // empty' "${response_file}")"

    if [[ -z "${new_token_id}" ]]; then
        echo "Konnect API did not return token id" >&2
        rm -f -- "${response_file}"
        return 1
    fi

    if [[ -z "${new_token}" ]]; then
        echo "Konnect API did not return token value" >&2
        rm -f -- "${response_file}"
        return 1
    fi

    jq -n \
        --arg token_id "${new_token_id}" \
        --arg token "${new_token}" \
        '{
            token_id: $token_id,
            token: $token
        }'

    rm -f -- "${response_file}"
}

delete_konnect_token() {
    local auth_token="$1"
    local system_account_id="$2"
    local token_id="$3"

    local response_file
    local http_status

    response_file="$(mktemp)"

    http_status="$(
        curl -sS \
            -o "${response_file}" \
            -w "%{http_code}" \
            --request DELETE \
            "${KONNECT_API_BASE}/system-accounts/${system_account_id}/access-tokens/${token_id}" \
            --header "Authorization: Bearer ${auth_token}" \
            --header "Accept: application/json"
    )"

    if [[ "${http_status}" -lt 200 || "${http_status}" -ge 300 ]]; then
        echo "Konnect delete token API failed." >&2
        echo "HTTP Status: ${http_status}" >&2
        echo "Response:" >&2
        cat "${response_file}" >&2
        rm -f -- "${response_file}"
        return 1
    fi

    rm -f -- "${response_file}"

    success "Token '${token_id}' deleted successfully"
}

rename_konnect_token() {
    local auth_token="$1"
    local system_account_id="$2"
    local token_id="$3"
    local new_name="$4"

    local response_file
    local http_status

    response_file="$(mktemp)"

    http_status="$(
        curl -sS \
            -o "${response_file}" \
            -w "%{http_code}" \
            --request PATCH \
            "${KONNECT_API_BASE}/system-accounts/${system_account_id}/access-tokens/${token_id}" \
            --header "Authorization: Bearer ${auth_token}" \
            --header "Content-Type: application/json" \
            --header "Accept: application/json" \
            --data "$(jq -n \
                --arg name "${new_name}" \
                '{
                    name: $name
                }'
            )"
    )"

    if [[ "${http_status}" -lt 200 || "${http_status}" -ge 300 ]]; then
        echo "Konnect rename token API failed." >&2
        echo "HTTP Status: ${http_status}" >&2
        echo "Response:" >&2
        cat "${response_file}" >&2
        rm -f -- "${response_file}"
        return 1
    fi

    rm -f -- "${response_file}"

    success "Token '${token_id}' renamed successfully to '${new_name}'"
}

###############################################################################
# Secret JSON Builder
###############################################################################

build_updated_secret_json() {
    local original_secret_json="$1"
    local new_token_id="$2"
    local new_token="$3"
    local expires_at="$4"

    if [[ "${TOKEN_TYPE}" == "api-ops" ]]; then

        jq \
            --arg token_id "${new_token_id}" \
            --arg token "${new_token}" \
            --arg expires_at "${expires_at}" \
            '
            .token_id = $token_id
            | .token = $token
            | .expires_at = $expires_at
            ' \
            <<< "${original_secret_json}"

    else

        jq \
            --arg token_id "${new_token_id}" \
            --arg token "${new_token}" \
            --arg expires_at "${expires_at}" \
            '
            .token_id = $token_id
            | .token = $token
            | .expires_at = $expires_at
            ' \
            <<< "${original_secret_json}"
    fi
}

###############################################################################
# Authentication Token
###############################################################################

get_auth_token() {

    if [[ -n "${KONNECT_ROTATION_ADMIN_TOKEN:-}" ]]; then
        debug "Authentication source: KONNECT_ROTATION_ADMIN_TOKEN"
        printf '%s' "${KONNECT_ROTATION_ADMIN_TOKEN}"
        return 0
    fi

    debug "Authentication source: Platform Ops Secret Manager token"
    debug "Authentication secret: ${PLATFORM_OPS_SECRET_NAME}"
    debug "Authentication project: us-prod-itg-api-kong-01"

    local platform_secret_json
    local platform_token

    ###########################################################################
    # Platform Ops authentication ALWAYS comes from PROD
    ###########################################################################

    platform_secret_json="$(
        fetch_secret \
            "${PLATFORM_OPS_SECRET_NAME}" \
            "us-prod-itg-api-kong-01"
    )"

    validate_secret_json \
        "${platform_secret_json}" \
        "${PLATFORM_OPS_SECRET_NAME}"

    platform_token="$(
        jq -r '.token // empty' <<< "${platform_secret_json}"
    )"

    [[ -n "${platform_token}" ]] ||
        fail "Platform Ops token is missing from ${PLATFORM_OPS_SECRET_NAME}"

    debug "Platform Ops authentication token found"
    debug "Token length: ${#platform_token}"

    printf '%s' "${platform_token}"
}

###############################################################################
# Common Secret Fields
###############################################################################

get_system_account_id() {
    local secret_json="$1"
    local secret_name="$2"

    local system_account_id

    system_account_id="$(
        jq -r '.system_account_id // empty' <<< "${secret_json}"
    )"

    [[ -n "${system_account_id}" ]] ||
        fail "system_account_id is missing in secret '${secret_name}'"

    printf '%s' "${system_account_id}"
}

get_old_token_id() {
    local secret_json="$1"

    jq -r '.token_id // empty' <<< "${secret_json}"
}

get_old_token() {
    local secret_json="$1"

    jq -r '.token // empty' <<< "${secret_json}"
}

###############################################################################
# Disable Previous Secret Manager Versions
###############################################################################

disable_old_secret_versions() {
    local secret_name="$1"
    local project="$2"

    log "Checking previous Secret Manager versions"
    log "Secret: ${secret_name}"

    local latest_version
    local enabled_versions

    ###########################################################################
    # Get latest version by create time
    ###########################################################################

    latest_version="$(
        gcloud secrets versions list "${secret_name}" \
            --project="${project}" \
            --filter="state=ENABLED" \
            --sort-by="~createTime" \
            --limit=1 \
            --format="value(name.basename())" |
        tr -d '[:space:]'
    )"

    [[ -n "${latest_version}" ]] || {
        fail "Unable to determine latest enabled version for secret '${secret_name}'"
    }

    log "Latest Secret Manager version: ${latest_version}"

    ###########################################################################
    # Get ALL enabled versions
    ###########################################################################

    enabled_versions="$(
        gcloud secrets versions list "${secret_name}" \
            --project="${project}" \
            --filter="state=ENABLED" \
            --format="value(name.basename())"
    )"

    [[ -n "${enabled_versions}" ]] || {
        success "No enabled Secret Manager versions found"
        return 0
    }

    ###########################################################################
    # Disable every enabled version EXCEPT the latest
    ###########################################################################

    local version
    local previous_versions_found=false

    while IFS= read -r version; do

        version="$(printf '%s' "${version}" | tr -d '[:space:]')"

        [[ -n "${version}" ]] || continue

        if [[ "${version}" == "${latest_version}" ]]; then
            log "Keeping latest Secret Manager version enabled: ${version}"
            continue
        fi

        previous_versions_found=true

        log "Disabling Secret Manager version: ${version}"

        local version_resource

        version_resource="projects/${project}/secrets/${secret_name}/versions/${version}"

        if gcloud secrets versions disable "${version_resource}" \
            --project="${project}" \
            >/dev/null; then

            success "Disabled Secret Manager version: ${version}"

        else

            fail "Failed to disable Secret Manager version: ${version}"

        fi

    done <<< "${enabled_versions}"

    ###########################################################################
    # Final result
    ###########################################################################

    if [[ "${previous_versions_found}" == false ]]; then

        success "No previous enabled Secret Manager versions found"

    else

        success "All previous enabled Secret Manager versions disabled"

    fi

    success "Latest Secret Manager version ${latest_version} remains enabled"
}

###############################################################################
# API Ops Rotation
###############################################################################
###############################################################################
# Delete existing API Ops token by permanent name
###############################################################################

delete_existing_api_ops_token_by_name() {

    local auth_token="$1"
    local system_account_id="$2"
    local token_name="$3"

    local token_list_json
    local existing_token_ids

    log "Checking for an existing API Ops token with permanent name"
    log "Token Name: ${token_name}"

    token_list_json="$(
        curl --silent --show-error --fail \
            --request GET \
            --header "Authorization: Bearer ${auth_token}" \
            --header "Content-Type: application/json" \
            "https://global.api.konghq.com/v3/system-accounts/${system_account_id}/access-tokens?size=100"
    )" || fail "Failed to list existing API Ops tokens"

    existing_token_ids="$(
        jq -r --arg token_name "${token_name}" '
            .data[]?
            | select(.name == $token_name)
            | .id // .token_id // empty
        ' <<< "${token_list_json}"
    )"

    if [[ -z "${existing_token_ids}" ]]; then
        log "No existing token found with permanent name"
        return 0
    fi

    while IFS= read -r existing_token_id; do

        [[ -n "${existing_token_id}" ]] || continue

        log "Existing permanent API Ops token found"
        log "Existing Token ID: ${existing_token_id}"
        log "Deleting existing permanent API Ops token"

        delete_konnect_token \
            "${auth_token}" \
            "${system_account_id}" \
            "${existing_token_id}"

        success "Existing permanent API Ops token deleted"
        success "Deleted Token ID: ${existing_token_id}"

    done <<< "${existing_token_ids}"
}


rotate_api_ops() {

    local secret_name="$1"

    log "=============================================="
    log "Starting API Ops token rotation"
    log "=============================================="

    ###########################################################################
    # Fetch API Ops Secret
    ###########################################################################

    local target_secret_json
    local system_account_id
    local old_token_id
    local old_token
    local auth_token

    log "Fetching API Ops Secret Manager secret"

    target_secret_json="$(
        fetch_secret \
            "${secret_name}" \
            "${GCP_PROJECT}"
    )"

    validate_secret_json \
        "${target_secret_json}" \
        "${secret_name}"

    ###########################################################################
    # Get System Account ID
    ###########################################################################

    system_account_id="$(
        get_system_account_id \
            "${target_secret_json}" \
            "${secret_name}"
    )"

    [[ -n "${system_account_id}" ]] ||
        fail "System Account ID was not found for ${secret_name}"

    ###########################################################################
    # Get existing token information
    ###########################################################################

    old_token_id="$(
        get_old_token_id "${target_secret_json}"
    )"

    old_token="$(
        get_old_token "${target_secret_json}"
    )"

    ###########################################################################
    # Platform Ops SAT is used for token management
    ###########################################################################

    log "Fetching global Platform Ops authentication token"

    auth_token="$(
        get_auth_token
    )"

    [[ -n "${auth_token}" ]] ||
        fail "Platform Ops authentication token was not retrieved"

    debug "Platform Ops authentication token retrieved successfully"
    debug "Authentication token length: ${#auth_token}"
    debug "Authentication token starts with: ${auth_token:0:8}..."

    local final_token_name
    local temporary_token_name
    local old_token_name
    local timestamp
    local expires_at

    timestamp="$(date -u '+%Y%m%d%H%M%S')"

    final_token_name="$(
        build_api_ops_token_name
    )"

    temporary_token_name="$(
        printf '%s-%s' \
            "${final_token_name}" \
            "${timestamp}"
    )"

    old_token_name="$(
        printf '%s-old-%s' \
            "${final_token_name}" \
            "${timestamp}"
    )"

    expires_at="$(
        get_expiry_date
    )"

    log "Secret Name       : ${secret_name}"
    log "System Account ID : ${system_account_id}"
    log "Final Token Name  : ${final_token_name}"
    log "Temporary Name    : ${temporary_token_name}"
    log "Old Token Name    : ${old_token_name}"
    log "Expires At        : ${expires_at}"

    ###########################################################################
    # ROTATION
    ###########################################################################

    if [[ -n "${old_token_id}" && -n "${old_token}" ]]; then

        #######################################################################
        # Rename OLD token
        #######################################################################

        log "Existing API Ops token found"
        log "Starting API Ops token rotation"

        log "Old Token ID       : ${old_token_id}"
        log "Old Token Name     : ${final_token_name}"
        log "Old Temporary Name : ${old_token_name}"

        rename_konnect_token \
            "${auth_token}" \
            "${system_account_id}" \
            "${old_token_id}" \
            "${old_token_name}"

        success "Old API Ops token moved to temporary name"

        #######################################################################
        # CREATE NEW TOKEN
        #######################################################################

        log "Creating new API Ops token"
        log "New Token Name: ${temporary_token_name}"

        local created_token_json
        local new_token_id
        local new_token

        created_token_json="$(
            create_konnect_token \
                "${auth_token}" \
                "${system_account_id}" \
                "${temporary_token_name}" \
                "${expires_at}"
        )"

        new_token_id="$(
            jq -r '.token_id // empty' <<< "${created_token_json}"
        )"

        new_token="$(
            jq -r '.token // empty' <<< "${created_token_json}"
        )"

        [[ -n "${new_token_id}" ]] ||
            fail "New API Ops token_id was not returned"

        [[ -n "${new_token}" ]] ||
            fail "New API Ops token was not returned"

        success "New API Ops token created successfully"
        success "New Token ID: ${new_token_id}"
        success "New Temporary Name: ${temporary_token_name}"

        #######################################################################
        # RENAME NEW TOKEN
        #######################################################################

        log "Renaming newly created API Ops token"
        log "New Token ID     : ${new_token_id}"
        log "Permanent Name   : ${final_token_name}"

        rename_konnect_token \
            "${auth_token}" \
            "${system_account_id}" \
            "${new_token_id}" \
            "${final_token_name}"

        success "New API Ops token renamed successfully"
        success "Permanent Token Name: ${final_token_name}"

        #######################################################################
        # UPDATE SECRET MANAGER
        #######################################################################

        local updated_secret_json

        updated_secret_json="$(
            build_updated_secret_json \
                "${target_secret_json}" \
                "${new_token_id}" \
                "${new_token}" \
                "${expires_at}"
        )"

        log "Updating API Ops Secret Manager secret"

        add_secret_version \
            "${secret_name}" \
            "${updated_secret_json}" \
            "${GCP_PROJECT}"

        success "API Ops Secret Manager updated successfully"

        #######################################################################
        # VERIFY SECRET MANAGER
        #######################################################################

        log "Verifying latest API Ops Secret Manager version"

        local latest_secret_json
        local latest_token_id

        latest_secret_json="$(
            fetch_secret \
                "${secret_name}" \
                "${GCP_PROJECT}"
        )"

        validate_secret_json \
            "${latest_secret_json}" \
            "${secret_name}"

        latest_token_id="$(
            jq -r '.token_id // empty' <<< "${latest_secret_json}"
        )"

        [[ "${latest_token_id}" == "${new_token_id}" ]] ||
            fail "API Ops Secret Manager verification failed"

        success "API Ops Secret Manager verification successful"

        #######################################################################
        # DELETE OLD TOKEN
        #######################################################################

        log "Deleting old API Ops token"
        log "Old Token ID: ${old_token_id}"

        delete_konnect_token \
            "${auth_token}" \
            "${system_account_id}" \
            "${old_token_id}"

        success "Old API Ops token deleted successfully"

        disable_old_secret_versions \
            "${secret_name}" \
            "${GCP_PROJECT}"

        #######################################################################
        # ROTATION COMPLETE
        #######################################################################

        success "=============================================="
        success "API Ops token rotation completed successfully"
        success "=============================================="

    else

        #######################################################################
        # INITIAL CREATION
        #######################################################################

        log "No existing API Ops token found"
        log "Initial API Ops token creation detected"

        #######################################################################
        # CREATE INITIAL TOKEN WITH TEMPORARY NAME
        #######################################################################

        log "Creating initial API Ops token"
        log "New Token Name: ${temporary_token_name}"

        local created_token_json
        local new_token_id
        local new_token

        created_token_json="$(
            create_konnect_token \
                "${auth_token}" \
                "${system_account_id}" \
                "${temporary_token_name}" \
                "${expires_at}"
        )"

        new_token_id="$(
            jq -r '.token_id // empty' <<< "${created_token_json}"
        )"

        new_token="$(
            jq -r '.token // empty' <<< "${created_token_json}"
        )"

        [[ -n "${new_token_id}" ]] ||
            fail "New API Ops token_id was not returned"

        [[ -n "${new_token}" ]] ||
            fail "New API Ops token was not returned"

        success "Initial API Ops token created successfully"
        success "New Token ID: ${new_token_id}"

        #######################################################################
        # DELETE EXISTING PERMANENT TOKEN IF PRESENT
        #######################################################################

        log "Checking whether an existing API Ops token already uses the permanent name"
        log "Permanent Name : ${final_token_name}"

        delete_existing_api_ops_token_by_name \
            "${auth_token}" \
            "${system_account_id}" \
            "${final_token_name}"

        #######################################################################
        # RENAME INITIAL TOKEN TO PERMANENT NAME
        #######################################################################

        log "Renaming initial API Ops token"
        log "Temporary Name : ${temporary_token_name}"
        log "Permanent Name : ${final_token_name}"

        rename_konnect_token \
            "${auth_token}" \
            "${system_account_id}" \
            "${new_token_id}" \
            "${final_token_name}"

        success "Initial API Ops token renamed successfully"
        success "Permanent Token Name: ${final_token_name}"

        #######################################################################
        # UPDATE SECRET MANAGER
        #######################################################################

        local updated_secret_json

        updated_secret_json="$(
            build_updated_secret_json \
                "${target_secret_json}" \
                "${new_token_id}" \
                "${new_token}" \
                "${expires_at}"
        )"

        log "Updating API Ops Secret Manager secret"

        add_secret_version \
            "${secret_name}" \
            "${updated_secret_json}" \
            "${GCP_PROJECT}"

        success "API Ops Secret Manager updated successfully"

        #######################################################################
        # VERIFY SECRET MANAGER
        #######################################################################

        log "Verifying latest API Ops Secret Manager version"

        local latest_secret_json
        local latest_token_id

        latest_secret_json="$(
            fetch_secret \
                "${secret_name}" \
                "${GCP_PROJECT}"
        )"

        validate_secret_json \
            "${latest_secret_json}" \
            "${secret_name}"

        latest_token_id="$(
            jq -r '.token_id // empty' <<< "${latest_secret_json}"
        )"

        [[ "${latest_token_id}" == "${new_token_id}" ]] ||
            fail "API Ops Secret Manager verification failed"

        success "API Ops Secret Manager verification successful"

        disable_old_secret_versions \
            "${secret_name}" \
            "${GCP_PROJECT}"

        #######################################################################
        # INITIAL CREATION COMPLETE
        #######################################################################

        success "=============================================="
        success "Initial API Ops token creation completed successfully"
        success "=============================================="

    fi
}

###############################################################################
# Platform Ops Rotation
###############################################################################

wait_for_token_name_available() {
    local auth_token="$1"
    local system_account_id="$2"
    local token_name="$3"

    local max_attempts="${4:-15}"
    local sleep_seconds="${5:-2}"

    local attempt
    local tokens_response
    local matching_token_id

    log "Waiting for Konnect to release token name: ${token_name}"

    for ((attempt=1; attempt<=max_attempts; attempt++)); do

        tokens_response="$(
            curl -sS \
                --fail-with-body \
                -X GET \
                "${KONNECT_API_BASE}/system-accounts/${system_account_id}/access-tokens" \
                -H "Authorization: Bearer ${auth_token}" \
                -H "Content-Type: application/json" \
                2>/dev/null
        )" || true

        matching_token_id="$(
            jq -r \
                --arg token_name "${token_name}" \
                '.data[]? | select(.name == $token_name) | .id' \
                <<< "${tokens_response}" \
                | head -n 1
        )"

        if [[ -z "${matching_token_id}" ]]; then
            log "Token name is now available: ${token_name}"
            return 0
        fi

        log "Attempt ${attempt}/${max_attempts}: token name still exists"
        debug "Existing token ID using ${token_name}: ${matching_token_id}"

        if (( attempt < max_attempts )); then
            sleep "${sleep_seconds}"
        fi
    done

    fail "Token name '${token_name}' is still occupied after ${max_attempts} attempts"
}

rotate_platform_ops() {
    local secret_name="${PLATFORM_OPS_SECRET_NAME}"
    local project="us-prod-itg-api-kong-01"

    log "=============================================="
    log "Starting Platform Ops token rotation"
    log "=============================================="

    local target_secret_json
    local system_account_id
    local old_token_id
    local old_token
    local auth_token
    local temporary_token_name
    local final_token_name
    local expires_at

    log "Fetching Platform Ops secret..."

    target_secret_json="$(
        fetch_secret \
            "${secret_name}" \
            "${project}"
    )"

    validate_secret_json \
        "${target_secret_json}" \
        "${secret_name}"

    ###########################################################################
    # Get Platform Ops system account ID
    ###########################################################################

    system_account_id="$(
        get_system_account_id \
            "${target_secret_json}" \
            "${secret_name}"
    )"

    ###########################################################################
    # Get existing token information
    ###########################################################################

    old_token_id="$(get_old_token_id "${target_secret_json}")"
    old_token="$(get_old_token "${target_secret_json}")"

    ###########################################################################
    # Get authentication token
    ###########################################################################

    log "Fetching Konnect authentication token..."

    auth_token="$(get_auth_token)"

    [[ -n "${auth_token}" ]] ||
        fail "Konnect authentication token was not retrieved"

    debug "Authentication token retrieved successfully"
    debug "Authentication token length: ${#auth_token}"
    debug "Authentication token starts with: ${auth_token:0:8}..."

    ###########################################################################
    # Build Platform Ops token names
    ###########################################################################

    temporary_token_name="$(build_platform_ops_timestamped_token_name)"
    final_token_name="$(build_platform_ops_final_token_name)"

    expires_at="$(get_expiry_date)"

    log "Secret Name       : ${secret_name}"
    log "System Account ID : ${system_account_id}"
    log "Temporary Name    : ${temporary_token_name}"
    log "Final Token Name  : ${final_token_name}"
    log "Expires At        : ${expires_at}"

    ###########################################################################
    # Create new token FIRST
    ###########################################################################

    log "Creating new Platform Ops token"

    local created_token_json
    local new_token_id
    local new_token

    created_token_json="$(
        create_konnect_token \
            "${auth_token}" \
            "${system_account_id}" \
            "${temporary_token_name}" \
            "${expires_at}"
    )"

    new_token_id="$(
        jq -r '.token_id // empty' <<< "${created_token_json}"
    )"

    new_token="$(
        jq -r '.token // empty' <<< "${created_token_json}"
    )"

    [[ -n "${new_token_id}" ]] ||
        fail "New Platform Ops token_id was not returned"

    [[ -n "${new_token}" ]] ||
        fail "New Platform Ops token was not returned"

    log "New Platform Ops token created successfully"
    log "New Token ID: ${new_token_id}"

    ###########################################################################
    # Update Secret Manager BEFORE deleting old token
    ###########################################################################

    local updated_secret_json

    updated_secret_json="$(
        build_updated_secret_json \
            "${target_secret_json}" \
            "${new_token_id}" \
            "${new_token}" \
            "${expires_at}"
    )"

    log "Updating Platform Ops Secret Manager secret"

    add_secret_version \
        "${secret_name}" \
        "${updated_secret_json}" \
        "${project}"

    log "Platform Ops Secret Manager updated successfully"

    ###########################################################################
    # Verify Secret Manager
    ###########################################################################

    log "Verifying latest Platform Ops Secret Manager version"

    local latest_secret_json
    local latest_token_id

    latest_secret_json="$(
        fetch_secret \
            "${secret_name}" \
            "${project}"
    )"

    validate_secret_json \
        "${latest_secret_json}" \
        "${secret_name}"

    latest_token_id="$(
        jq -r '.token_id // empty' <<< "${latest_secret_json}"
    )"

    [[ "${latest_token_id}" == "${new_token_id}" ]] ||
        fail "Platform Ops Secret Manager verification failed"

    success "Platform Ops Secret Manager verification successful"

    ###########################################################################
    # Prepare temporary name for OLD Platform Ops token
    ###########################################################################

    local old_platform_ops_token_name

    old_platform_ops_token_name="$(
        printf '%s-old-%s' \
            "${PLATFORM_OPS_TOKEN_BASE_NAME}" \
            "$(date -u '+%Y%m%d%H%M%S')"
    )"

    ###########################################################################
    # Rename OLD token temporarily
    ###########################################################################

    if [[ -n "${old_token_id}" && -n "${old_token}" ]]; then

        log "Renaming old Platform Ops token temporarily"
        log "Temporary old token name: ${old_platform_ops_token_name}"

        rename_konnect_token \
            "${auth_token}" \
            "${system_account_id}" \
            "${old_token_id}" \
            "${old_platform_ops_token_name}"

        success "Old Platform Ops token moved to temporary name"

        wait_for_token_name_available \
            "${auth_token}" \
            "${system_account_id}" \
            "${final_token_name}" \
            15 \
            2

    else

        log "No old Platform Ops token found"
        log "Permanent token name should already be available"
    fi

    ###########################################################################
    # Rename NEW token to the permanent Platform Ops token name
    ###########################################################################

    log "Renaming newly created Platform Ops token"
    log "New token ID: ${new_token_id}"
    log "Permanent token name: ${final_token_name}"

    rename_konnect_token \
        "${auth_token}" \
        "${system_account_id}" \
        "${new_token_id}" \
        "${final_token_name}"

    success "New Platform Ops token renamed successfully to: ${final_token_name}"

    ###########################################################################
    # Delete OLD token
    ###########################################################################

    if [[ -n "${old_token_id}" && -n "${old_token}" ]]; then

        log "Deleting old Platform Ops token"

        delete_konnect_token \
            "${auth_token}" \
            "${system_account_id}" \
            "${old_token_id}"

        success "Old Platform Ops token deleted successfully"

    else

        log "No old Platform Ops token found"
        log "Skipping old token deletion"

    fi

    disable_old_secret_versions \
        "${secret_name}" \
        "${project}"

    ###########################################################################
    # Complete
    ###########################################################################

    success "=============================================="
    success "Platform Ops token rotation completed successfully"
    success "=============================================="
}

###############################################################################
# Main
###############################################################################

main()
{
    ###########################################################################
    # Validate arguments BEFORE prerequisites
    ###########################################################################

    if [[ $# -eq 0 ]]; then
        echo "ERROR: No arguments provided." >&2
        usage >&2
        exit 1
    fi

    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        usage
        exit 0
    fi

    ###########################################################################
    # Validate prerequisites
    ###########################################################################

    validate_prerequisites

    ###########################################################################
    # Initialize arguments
    ###########################################################################

    TOKEN_TYPE=""

    ENV_NAME=""
    CP_TYPE=""
    TTL_DAYS=""

    ###########################################################################
    # Platform Ops
    ###########################################################################

    if [[ "$1" == "platform-ops" ]]; then

        TOKEN_TYPE="platform-ops"

        #######################################################################
        # Platform Ops is ALWAYS PROD
        #######################################################################

        ENV_NAME="prd"
        TTL_DAYS="${2:-${DEFAULT_TTL_DAYS}}"

        if [[ $# -gt 2 ]]; then
            fail "Too many arguments for Platform Ops rotation."
        fi

        validate_ttl "${TTL_DAYS}"

        set_gcp_project

        PLATFORM_OPS_SECRET_NAME="$(
            build_platform_ops_secret_name "prd"
        )"

    ###########################################################################
    # API Ops
    ###########################################################################

    elif [[ $# -eq 4 ]]; then

        ENV_NAME="$1"
        TOKEN_TYPE="$2"
        TTL_DAYS="$3"
        CP_TYPE="$4"

        if [[ "${TOKEN_TYPE}" != "api-ops" ]]; then
            fail "Invalid token type '${TOKEN_TYPE}'. Expected: api-ops"
        fi

        validate_api_environment "${ENV_NAME}"

        validate_cp_type "${CP_TYPE}"

        validate_ttl "${TTL_DAYS}"

        #######################################################################
        # API Ops target project remains environment-specific
        #######################################################################

        set_gcp_project

        #######################################################################
        # BUT Platform Ops authentication is ALWAYS PROD
        #######################################################################

        PLATFORM_OPS_SECRET_NAME="$(
            build_platform_ops_secret_name "prd"
        )"

    ###########################################################################
    # Invalid argument count
    ###########################################################################

    else

        echo "ERROR: Invalid arguments." >&2
        usage >&2
        exit 1

    fi

    ###########################################################################
    # Display configuration
    ###########################################################################

    set_gcp_project

    log "=============================================="
    log "Kong Konnect Token Rotation"
    log "=============================================="

    log "Token Type : ${TOKEN_TYPE}"
    log "TTL Days   : ${TTL_DAYS}"
    log "GCP Project: ${GCP_PROJECT}"
    log "Konnect API: ${KONNECT_API_BASE}"

    ###########################################################################
    # Execute rotation
    ###########################################################################

    if [[ "${TOKEN_TYPE}" == "api-ops" ]]; then

        log "Environment: ${ENV_NAME}"
        log "CP Type    : ${CP_TYPE}"

        local secret_name

        secret_name="$(
            build_api_ops_secret_name \
                "${ENV_NAME}" \
                "${CP_TYPE}"
        )"

        rotate_api_ops "${secret_name}"

    else

        log "Platform Ops Project: us-prod-itg-api-kong-01"
        log "Secret Name: ${PLATFORM_OPS_SECRET_NAME}"

        rotate_platform_ops

    fi
}

main "$@"

# #!/usr/bin/env bash

# set -Eeuo pipefail

# SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# # shellcheck source=common/fetch_konnect_token.sh
# source "${SCRIPT_DIR}/../common/fetch_konnect_token.sh"
# ###############################################################################
# # Global Configuration
# ###############################################################################

# KONNECT_API_BASE="${KONNECT_API_BASE:-https://global.api.konghq.com/v3}"
# PLATFORM_OPS_SECRET_NAME=""
# PLATFORM_OPS_TOKEN_BASE_NAME="konnect-platform-ops-cp-admin-sat"
# DEFAULT_TTL_DAYS="${TOKEN_TTL_DAYS:-365}"

# ###############################################################################
# # Logging / Error Handling
# ###############################################################################

# RED='\033[0;31m'
# GREEN='\033[0;32m'
# YELLOW='\033[1;33m'
# BLUE='\033[0;34m'
# NC='\033[0m'

# log() {
#     printf '%b%s%b\n' "${BLUE}" "$*" "${NC}"
# }

# success() {
#     printf '%b[SUCCESS] %s%b\n' "${GREEN}" "$*" "${NC}"
# }

# debug() {
#     printf '%b[DEBUG] %s%b\n' "${YELLOW}" "$*" "${NC}" >&2
# }

# fail() {
#     printf '%b[ERROR] %s%b\n' "${RED}" "$*" "${NC}" >&2
#     exit 1
# }

# ###############################################################################
# # Usage
# ###############################################################################

# usage() {
# cat <<'EOF'

# Usage:
# API Ops      : ./token-rotation.sh <env> api-ops <ttl-days> <cp-type>
# Platform Ops : ./token-rotation.sh platform-ops [ttl-days]

# Examples:
# ./token-rotation.sh dev api-ops 365 dc
# ./token-rotation.sh platform-ops 365

# Allowed:
# env      : dev | uat | ppd | prd
# cp-type  : onprem | gcloud
# ttl-days : 1-365 (default: 365)

# EOF
# }

# ###############################################################################
# # Prerequisites
# ###############################################################################

# require_command() {
#     command -v "$1" >/dev/null 2>&1 ||
#         fail "Required command not found: $1"
# }

# validate_prerequisites() {
#     require_command gcloud
#     require_command jq
#     require_command curl
#     require_command date
# }

# ###############################################################################
# # Argument Validation
# ###############################################################################

# validate_api_environment() {
#     local env_name="$1"

#     case "${env_name}" in
#         dev|uat|ppd|prd)
#             ;;
#         *)
#             fail "Invalid environment '${env_name}'. Allowed values: dev, uat, ppd, prd"
#             ;;
#     esac
# }

# validate_cp_type() {
#     local cp_type="$1"

#     case "${cp_type}" in
#         onprem|gcloud)
#             ;;
#         *)
#             fail "Invalid cp-type '${cp_type}'. Allowed values: onprem, gcloud"
#             ;;
#     esac
# }

# validate_ttl() {
#     local ttl="$1"

#     [[ "${ttl}" =~ ^[0-9]+$ ]] ||
#         fail "TTL must be a positive integer. Received: ${ttl}"

#     (( ttl > 0 )) ||
#         fail "TTL must be greater than 0"

#     if (( ttl > 365 )); then
#         fail "TTL cannot exceed 365 days because Konnect system account tokens have a maximum duration of 12 months"
#     fi
# }

# ###############################################################################
# # Set GCP Project Based on Environment
# ###############################################################################

# set_gcp_project() {
#     case "${ENV_NAME}" in

#         dev|uat)
#             GCP_PROJECT="us-nprd-itg-api-kong-01"
#             ;;

#         ppd)
#             GCP_PROJECT="us-pprd-itg-api-kong-01"
#             ;;

#         prd)
#             GCP_PROJECT="us-prod-itg-api-kong-01"
#             ;;
#     esac

#     export GCP_PROJECT
# }

# ###############################################################################
# # Secret Name Functions
# ###############################################################################

# build_api_ops_secret_name() {
#     local env_name="$1"
#     local cp_type="$2"
#     local project_prefix

#     case "${env_name}" in
#         dev|uat)
#             project_prefix="us-nprd"
#             ;;
#         ppd)
#             project_prefix="us-pprd"
#             ;;
#         prd)
#             project_prefix="us-prod"
#             ;;
#         *)
#             fail "Unable to determine secret prefix for environment: ${env_name}"
#             ;;
#     esac

#     echo "${project_prefix}-itg-api-kong-konnect-${cp_type}-cp-info-${env_name}"
# }

# get_secret_name() {

#     local token_type="${TOKEN_TYPE:-}"
#     local environment="${ENVIRONMENT:-}"
#     local cp_type="${CP_TYPE:-}"

#     if [[ "${token_type}" == "platform-ops" ]]; then
#         echo "${PLATFORM_OPS_SECRET_NAME}"
#         return
#     fi

#     if [[ -z "${environment}" ]]; then
#         fail "Environment is empty while resolving API Ops secret name"
#     fi

#     if [[ -z "${cp_type}" ]]; then
#         fail "Control plane type is empty while resolving API Ops secret name"
#     fi

#     build_api_ops_secret_name "${environment}" "${cp_type}"
# }

# build_platform_ops_secret_name() {
#     local env_name="$1"
#     local project_prefix

#     case "${env_name}" in
#         dev|uat|test)
#             project_prefix="us-nprd"
#             ;;
#         ppd)
#             project_prefix="us-pprd"
#             ;;
#         prd)
#             project_prefix="us-prod"
#             ;;
#         *)
#             fail "Unable to determine secret prefix for environment: ${env_name}"
#             ;;
#     esac

#     echo "${project_prefix}-itg-api-kong-konnect-platform-ops-sat-info"
# }

# ###############################################################################
# # Token Name Functions
# ###############################################################################

# build_api_ops_token_name() {
#     echo "${ENV_NAME}-${CP_TYPE}-api-ops-deployer-sat"
# }

# build_platform_ops_timestamped_token_name() {
#     local timestamp

#     timestamp="$(date -u '+%Y%m%d%H%M%S')"

#     echo "${PLATFORM_OPS_TOKEN_BASE_NAME}-${timestamp}"
# }

# build_platform_ops_final_token_name() {
#     echo "${PLATFORM_OPS_TOKEN_BASE_NAME}"
# }

# ###############################################################################
# # Date Functions
# ###############################################################################

# get_expiry_date() {
#     date -u -d "+${TTL_DAYS} days" '+%Y-%m-%dT%H:%M:%SZ'
# }

# ###############################################################################
# # GCP Secret Manager
# ###############################################################################

# fetch_secret() {
#     local secret_name="$1"
#     local project="$2"

#     debug "----------------------------------------------"
#     debug "GCP Secret Manager processing"
#     debug "----------------------------------------------"
#     debug "Requested Secret : ${secret_name}"
#     debug "GCP Project      : ${project}"

#     gcloud secrets versions access latest \
#         --secret="${secret_name}" \
#         --project="${project}"
# }

# add_secret_version() {
#     local secret_name="$1"
#     local secret_json="$2"
#     local project="$3"

#     printf '%s' "${secret_json}" |
#         gcloud secrets versions add "${secret_name}" \
#             --project="${project}" \
#             --data-file=- \
#             >/dev/null
# }

# ###############################################################################
# # Secret Validation
# ###############################################################################

# validate_secret_json() {
#     local secret_json="$1"
#     local secret_name="$2"

#     echo "${secret_json}" | jq empty >/dev/null 2>&1 ||
#         fail "Secret '${secret_name}' does not contain valid JSON"
# }

# ###############################################################################
# # Konnect API
# ###############################################################################

# create_konnect_token() {
#     local auth_token="$1"
#     local system_account_id="$2"
#     local token_name="$3"
#     local expires_at="$4"

#     local response_file
#     local http_status

#     response_file="$(mktemp)"

#     http_status="$(
#         curl -sS \
#             -o "${response_file}" \
#             -w "%{http_code}" \
#             --request POST \
#             "${KONNECT_API_BASE}/system-accounts/${system_account_id}/access-tokens" \
#             --header "Authorization: Bearer ${auth_token}" \
#             --header "Content-Type: application/json" \
#             --header "Accept: application/json" \
#             --data "$(jq -n \
#                 --arg name "${token_name}" \
#                 --arg expires_at "${expires_at}" \
#                 '{
#                     name: $name,
#                     expires_at: $expires_at
#                 }'
#             )"
#     )"

#     if [[ "${http_status}" -lt 200 || "${http_status}" -ge 300 ]]; then
#         echo "Konnect create token API failed." >&2
#         echo "HTTP Status: ${http_status}" >&2
#         echo "Response:" >&2
#         cat "${response_file}" >&2
#         rm -f -- "${response_file}"
#         return 1
#     fi

#     local new_token_id
#     local new_token

#     new_token_id="$(jq -r '.id // empty' "${response_file}")"
#     new_token="$(jq -r '.token // empty' "${response_file}")"

#     if [[ -z "${new_token_id}" ]]; then
#         echo "Konnect API did not return token id" >&2
#         rm -f -- "${response_file}"
#         return 1
#     fi

#     if [[ -z "${new_token}" ]]; then
#         echo "Konnect API did not return token value" >&2
#         rm -f -- "${response_file}"
#         return 1
#     fi

#     jq -n \
#         --arg token_id "${new_token_id}" \
#         --arg token "${new_token}" \
#         '{
#             token_id: $token_id,
#             token: $token
#         }'

#     rm -f -- "${response_file}"
# }

# delete_konnect_token() {
#     local auth_token="$1"
#     local system_account_id="$2"
#     local token_id="$3"

#     local response_file
#     local http_status

#     response_file="$(mktemp)"

#     http_status="$(
#         curl -sS \
#             -o "${response_file}" \
#             -w "%{http_code}" \
#             --request DELETE \
#             "${KONNECT_API_BASE}/system-accounts/${system_account_id}/access-tokens/${token_id}" \
#             --header "Authorization: Bearer ${auth_token}" \
#             --header "Accept: application/json"
#     )"

#     if [[ "${http_status}" -lt 200 || "${http_status}" -ge 300 ]]; then
#         echo "Konnect delete token API failed." >&2
#         echo "HTTP Status: ${http_status}" >&2
#         echo "Response:" >&2
#         cat "${response_file}" >&2
#         rm -f -- "${response_file}"
#         return 1
#     fi

#     rm -f -- "${response_file}"

#     success "Token '${token_id}' deleted successfully"
# }

# rename_konnect_token() {
#     local auth_token="$1"
#     local system_account_id="$2"
#     local token_id="$3"
#     local new_name="$4"

#     local response_file
#     local http_status

#     response_file="$(mktemp)"

#     http_status="$(
#         curl -sS \
#             -o "${response_file}" \
#             -w "%{http_code}" \
#             --request PATCH \
#             "${KONNECT_API_BASE}/system-accounts/${system_account_id}/access-tokens/${token_id}" \
#             --header "Authorization: Bearer ${auth_token}" \
#             --header "Content-Type: application/json" \
#             --header "Accept: application/json" \
#             --data "$(jq -n \
#                 --arg name "${new_name}" \
#                 '{
#                     name: $name
#                 }'
#             )"
#     )"

#     if [[ "${http_status}" -lt 200 || "${http_status}" -ge 300 ]]; then
#         echo "Konnect rename token API failed." >&2
#         echo "HTTP Status: ${http_status}" >&2
#         echo "Response:" >&2
#         cat "${response_file}" >&2
#         rm -f -- "${response_file}"
#         return 1
#     fi

#     rm -f -- "${response_file}"

#     success "Token '${token_id}' renamed successfully to '${new_name}'"
# }

# ###############################################################################
# # Secret JSON Builder
# ###############################################################################

# build_updated_secret_json() {
#     local original_secret_json="$1"
#     local new_token_id="$2"
#     local new_token="$3"
#     local expires_at="$4"

#     if [[ "${TOKEN_TYPE}" == "api-ops" ]]; then

#         jq \
#             --arg token_id "${new_token_id}" \
#             --arg token "${new_token}" \
#             --arg expires_at "${expires_at}" \
#             '
#             .token_id = $token_id
#             | .token = $token
#             | .expires_at = $expires_at
#             ' \
#             <<< "${original_secret_json}"

#     else

#         jq \
#             --arg token_id "${new_token_id}" \
#             --arg token "${new_token}" \
#             --arg expires_at "${expires_at}" \
#             '
#             .token_id = $token_id
#             | .token = $token
#             | .expires_at = $expires_at
#             ' \
#             <<< "${original_secret_json}"
#     fi
# }

# ###############################################################################
# # Authentication Token
# ###############################################################################

# get_auth_token() {

#     if [[ -n "${KONNECT_ROTATION_ADMIN_TOKEN:-}" ]]; then
#         debug "Authentication source: KONNECT_ROTATION_ADMIN_TOKEN"
#         printf '%s' "${KONNECT_ROTATION_ADMIN_TOKEN}"
#         return 0
#     fi

#     debug "Authentication source: Platform Ops Secret Manager token"
#     debug "Authentication secret: ${PLATFORM_OPS_SECRET_NAME}"
#     debug "Authentication project: us-prod-itg-api-kong-01"

#     local platform_secret_json
#     local platform_token

#     ###########################################################################
#     # Platform Ops authentication ALWAYS comes from PROD
#     ###########################################################################

#     platform_secret_json="$(
#         fetch_secret \
#             "${PLATFORM_OPS_SECRET_NAME}" \
#             "us-prod-itg-api-kong-01"
#     )"

#     validate_secret_json \
#         "${platform_secret_json}" \
#         "${PLATFORM_OPS_SECRET_NAME}"

#     platform_token="$(
#         jq -r '.token // empty' <<< "${platform_secret_json}"
#     )"

#     [[ -n "${platform_token}" ]] ||
#         fail "Platform Ops token is missing from ${PLATFORM_OPS_SECRET_NAME}"

#     debug "Platform Ops authentication token found"
#     debug "Token length: ${#platform_token}"

#     printf '%s' "${platform_token}"
# }

# ###############################################################################
# # Common Secret Fields
# ###############################################################################

# get_system_account_id() {
#     local secret_json="$1"
#     local secret_name="$2"

#     local system_account_id

#     system_account_id="$(
#         jq -r '.system_account_id // empty' <<< "${secret_json}"
#     )"

#     [[ -n "${system_account_id}" ]] ||
#         fail "system_account_id is missing in secret '${secret_name}'"

#     printf '%s' "${system_account_id}"
# }

# get_old_token_id() {
#     local secret_json="$1"

#     jq -r '.token_id // empty' <<< "${secret_json}"
# }

# get_old_token() {
#     local secret_json="$1"

#     jq -r '.token // empty' <<< "${secret_json}"
# }

# ###############################################################################
# # Disable Previous Secret Manager Versions
# ###############################################################################

# disable_old_secret_versions() {
#     local secret_name="$1"
#     local project="$2"

#     log "Checking previous Secret Manager versions"
#     log "Secret: ${secret_name}"

#     local latest_version
#     local enabled_versions

#     ###########################################################################
#     # Get latest version by create time
#     ###########################################################################

#     latest_version="$(
#         gcloud secrets versions list "${secret_name}" \
#             --project="${project}" \
#             --filter="state=ENABLED" \
#             --sort-by="~createTime" \
#             --limit=1 \
#             --format="value(name.basename())" |
#         tr -d '[:space:]'
#     )"

#     [[ -n "${latest_version}" ]] || {
#         fail "Unable to determine latest enabled version for secret '${secret_name}'"
#     }

#     log "Latest Secret Manager version: ${latest_version}"

#     ###########################################################################
#     # Get ALL enabled versions
#     ###########################################################################

#     enabled_versions="$(
#         gcloud secrets versions list "${secret_name}" \
#             --project="${project}" \
#             --filter="state=ENABLED" \
#             --format="value(name.basename())"
#     )"

#     [[ -n "${enabled_versions}" ]] || {
#         success "No enabled Secret Manager versions found"
#         return 0
#     }

#     ###########################################################################
#     # Disable every enabled version EXCEPT the latest
#     ###########################################################################

#     local version
#     local previous_versions_found=false

#     while IFS= read -r version; do

#         version="$(printf '%s' "${version}" | tr -d '[:space:]')"

#         [[ -n "${version}" ]] || continue

#         if [[ "${version}" == "${latest_version}" ]]; then
#             log "Keeping latest Secret Manager version enabled: ${version}"
#             continue
#         fi

#         previous_versions_found=true

#         log "Disabling Secret Manager version: ${version}"

#         local version_resource

#         version_resource="projects/${project}/secrets/${secret_name}/versions/${version}"

#         if gcloud secrets versions disable "${version_resource}" \
#             --project="${project}" \
#             >/dev/null; then

#             success "Disabled Secret Manager version: ${version}"

#         else

#             fail "Failed to disable Secret Manager version: ${version}"

#         fi

#     done <<< "${enabled_versions}"

#     ###########################################################################
#     # Final result
#     ###########################################################################

#     if [[ "${previous_versions_found}" == false ]]; then

#         success "No previous enabled Secret Manager versions found"

#     else

#         success "All previous enabled Secret Manager versions disabled"

#     fi

#     success "Latest Secret Manager version ${latest_version} remains enabled"
# }

# ###############################################################################
# # API Ops Rotation
# ###############################################################################
# ###############################################################################
# # Delete existing API Ops token by permanent name
# ###############################################################################

# delete_existing_api_ops_token_by_name() {

#     local auth_token="$1"
#     local system_account_id="$2"
#     local token_name="$3"

#     local token_list_json
#     local existing_token_ids

#     log "Checking for an existing API Ops token with permanent name"
#     log "Token Name: ${token_name}"

#     token_list_json="$(
#         curl --silent --show-error --fail \
#             --request GET \
#             --header "Authorization: Bearer ${auth_token}" \
#             --header "Content-Type: application/json" \
#             "https://global.api.konghq.com/v3/system-accounts/${system_account_id}/access-tokens?size=100"
#     )" || fail "Failed to list existing API Ops tokens"

#     existing_token_ids="$(
#         jq -r --arg token_name "${token_name}" '
#             .data[]?
#             | select(.name == $token_name)
#             | .id // .token_id // empty
#         ' <<< "${token_list_json}"
#     )"

#     if [[ -z "${existing_token_ids}" ]]; then
#         log "No existing token found with permanent name"
#         return 0
#     fi

#     while IFS= read -r existing_token_id; do

#         [[ -n "${existing_token_id}" ]] || continue

#         log "Existing permanent API Ops token found"
#         log "Existing Token ID: ${existing_token_id}"
#         log "Deleting existing permanent API Ops token"

#         delete_konnect_token \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${existing_token_id}"

#         success "Existing permanent API Ops token deleted"
#         success "Deleted Token ID: ${existing_token_id}"

#     done <<< "${existing_token_ids}"
# }


# rotate_api_ops() {

#     local secret_name="$1"

#     log "=============================================="
#     log "Starting API Ops token rotation"
#     log "=============================================="

#     ###########################################################################
#     # Fetch API Ops Secret
#     ###########################################################################

#     local target_secret_json
#     local system_account_id
#     local old_token_id
#     local old_token
#     local auth_token

#     log "Fetching API Ops Secret Manager secret"

#     target_secret_json="$(
#         fetch_secret \
#             "${secret_name}" \
#             "${GCP_PROJECT}"
#     )"

#     validate_secret_json \
#         "${target_secret_json}" \
#         "${secret_name}"

#     ###########################################################################
#     # Get System Account ID
#     ###########################################################################

#     system_account_id="$(
#         get_system_account_id \
#             "${target_secret_json}" \
#             "${secret_name}"
#     )"

#     [[ -n "${system_account_id}" ]] ||
#         fail "System Account ID was not found for ${secret_name}"

#     ###########################################################################
#     # Get existing token information
#     ###########################################################################

#     old_token_id="$(
#         get_old_token_id "${target_secret_json}"
#     )"

#     old_token="$(
#         get_old_token "${target_secret_json}"
#     )"

#     ###########################################################################
#     # Platform Ops SAT is used for token management
#     ###########################################################################

#     log "Fetching global Platform Ops authentication token"

#     auth_token="$(
#         get_auth_token
#     )"

#     [[ -n "${auth_token}" ]] ||
#         fail "Platform Ops authentication token was not retrieved"

#     debug "Platform Ops authentication token retrieved successfully"
#     debug "Authentication token length: ${#auth_token}"
#     debug "Authentication token starts with: ${auth_token:0:8}..."

#     local final_token_name
#     local temporary_token_name
#     local old_token_name
#     local timestamp
#     local expires_at

#     timestamp="$(date -u '+%Y%m%d%H%M%S')"

#     final_token_name="$(
#         build_api_ops_token_name
#     )"

#     temporary_token_name="$(
#         printf '%s-%s' \
#             "${final_token_name}" \
#             "${timestamp}"
#     )"

#     old_token_name="$(
#         printf '%s-old-%s' \
#             "${final_token_name}" \
#             "${timestamp}"
#     )"

#     expires_at="$(
#         get_expiry_date
#     )"

#     log "Secret Name       : ${secret_name}"
#     log "System Account ID : ${system_account_id}"
#     log "Final Token Name  : ${final_token_name}"
#     log "Temporary Name    : ${temporary_token_name}"
#     log "Old Token Name    : ${old_token_name}"
#     log "Expires At        : ${expires_at}"

#     ###########################################################################
#     # ROTATION
#     ###########################################################################

#     if [[ -n "${old_token_id}" && -n "${old_token}" ]]; then

#         #######################################################################
#         # Rename OLD token
#         #######################################################################

#         log "Existing API Ops token found"
#         log "Starting API Ops token rotation"

#         log "Old Token ID       : ${old_token_id}"
#         log "Old Token Name     : ${final_token_name}"
#         log "Old Temporary Name : ${old_token_name}"

#         rename_konnect_token \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${old_token_id}" \
#             "${old_token_name}"

#         success "Old API Ops token moved to temporary name"

#         #######################################################################
#         # CREATE NEW TOKEN
#         #######################################################################

#         log "Creating new API Ops token"
#         log "New Token Name: ${temporary_token_name}"

#         local created_token_json
#         local new_token_id
#         local new_token

#         created_token_json="$(
#             create_konnect_token \
#                 "${auth_token}" \
#                 "${system_account_id}" \
#                 "${temporary_token_name}" \
#                 "${expires_at}"
#         )"

#         new_token_id="$(
#             jq -r '.token_id // empty' <<< "${created_token_json}"
#         )"

#         new_token="$(
#             jq -r '.token // empty' <<< "${created_token_json}"
#         )"

#         [[ -n "${new_token_id}" ]] ||
#             fail "New API Ops token_id was not returned"

#         [[ -n "${new_token}" ]] ||
#             fail "New API Ops token was not returned"

#         success "New API Ops token created successfully"
#         success "New Token ID: ${new_token_id}"
#         success "New Temporary Name: ${temporary_token_name}"

#         #######################################################################
#         # RENAME NEW TOKEN
#         #######################################################################

#         log "Renaming newly created API Ops token"
#         log "New Token ID     : ${new_token_id}"
#         log "Permanent Name   : ${final_token_name}"

#         rename_konnect_token \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${new_token_id}" \
#             "${final_token_name}"

#         success "New API Ops token renamed successfully"
#         success "Permanent Token Name: ${final_token_name}"

#         #######################################################################
#         # UPDATE SECRET MANAGER
#         #######################################################################

#         local updated_secret_json

#         updated_secret_json="$(
#             build_updated_secret_json \
#                 "${target_secret_json}" \
#                 "${new_token_id}" \
#                 "${new_token}" \
#                 "${expires_at}"
#         )"

#         log "Updating API Ops Secret Manager secret"

#         add_secret_version \
#             "${secret_name}" \
#             "${updated_secret_json}" \
#             "${GCP_PROJECT}"

#         success "API Ops Secret Manager updated successfully"

#         #######################################################################
#         # VERIFY SECRET MANAGER
#         #######################################################################

#         log "Verifying latest API Ops Secret Manager version"

#         local latest_secret_json
#         local latest_token_id

#         latest_secret_json="$(
#             fetch_secret \
#                 "${secret_name}" \
#                 "${GCP_PROJECT}"
#         )"

#         validate_secret_json \
#             "${latest_secret_json}" \
#             "${secret_name}"

#         latest_token_id="$(
#             jq -r '.token_id // empty' <<< "${latest_secret_json}"
#         )"

#         [[ "${latest_token_id}" == "${new_token_id}" ]] ||
#             fail "API Ops Secret Manager verification failed"

#         success "API Ops Secret Manager verification successful"

#         #######################################################################
#         # DELETE OLD TOKEN
#         #######################################################################

#         log "Deleting old API Ops token"
#         log "Old Token ID: ${old_token_id}"

#         delete_konnect_token \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${old_token_id}"

#         success "Old API Ops token deleted successfully"

#         disable_old_secret_versions \
#             "${secret_name}" \
#             "${GCP_PROJECT}"

#         #######################################################################
#         # ROTATION COMPLETE
#         #######################################################################

#         success "=============================================="
#         success "API Ops token rotation completed successfully"
#         success "=============================================="

#     else

#         #######################################################################
#         # INITIAL CREATION
#         #######################################################################

#         log "No existing API Ops token found"
#         log "Initial API Ops token creation detected"

#         #######################################################################
#         # CREATE INITIAL TOKEN WITH TEMPORARY NAME
#         #######################################################################

#         log "Creating initial API Ops token"
#         log "New Token Name: ${temporary_token_name}"

#         local created_token_json
#         local new_token_id
#         local new_token

#         created_token_json="$(
#             create_konnect_token \
#                 "${auth_token}" \
#                 "${system_account_id}" \
#                 "${temporary_token_name}" \
#                 "${expires_at}"
#         )"

#         new_token_id="$(
#             jq -r '.token_id // empty' <<< "${created_token_json}"
#         )"

#         new_token="$(
#             jq -r '.token // empty' <<< "${created_token_json}"
#         )"

#         [[ -n "${new_token_id}" ]] ||
#             fail "New API Ops token_id was not returned"

#         [[ -n "${new_token}" ]] ||
#             fail "New API Ops token was not returned"

#         success "Initial API Ops token created successfully"
#         success "New Token ID: ${new_token_id}"

#         #######################################################################
#         # DELETE EXISTING PERMANENT TOKEN IF PRESENT
#         #######################################################################

#         log "Checking whether an existing API Ops token already uses the permanent name"
#         log "Permanent Name : ${final_token_name}"

#         delete_existing_api_ops_token_by_name \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${final_token_name}"

#         #######################################################################
#         # RENAME INITIAL TOKEN TO PERMANENT NAME
#         #######################################################################

#         log "Renaming initial API Ops token"
#         log "Temporary Name : ${temporary_token_name}"
#         log "Permanent Name : ${final_token_name}"

#         rename_konnect_token \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${new_token_id}" \
#             "${final_token_name}"

#         success "Initial API Ops token renamed successfully"
#         success "Permanent Token Name: ${final_token_name}"

#         #######################################################################
#         # UPDATE SECRET MANAGER
#         #######################################################################

#         local updated_secret_json

#         updated_secret_json="$(
#             build_updated_secret_json \
#                 "${target_secret_json}" \
#                 "${new_token_id}" \
#                 "${new_token}" \
#                 "${expires_at}"
#         )"

#         log "Updating API Ops Secret Manager secret"

#         add_secret_version \
#             "${secret_name}" \
#             "${updated_secret_json}" \
#             "${GCP_PROJECT}"

#         success "API Ops Secret Manager updated successfully"

#         #######################################################################
#         # VERIFY SECRET MANAGER
#         #######################################################################

#         log "Verifying latest API Ops Secret Manager version"

#         local latest_secret_json
#         local latest_token_id

#         latest_secret_json="$(
#             fetch_secret \
#                 "${secret_name}" \
#                 "${GCP_PROJECT}"
#         )"

#         validate_secret_json \
#             "${latest_secret_json}" \
#             "${secret_name}"

#         latest_token_id="$(
#             jq -r '.token_id // empty' <<< "${latest_secret_json}"
#         )"

#         [[ "${latest_token_id}" == "${new_token_id}" ]] ||
#             fail "API Ops Secret Manager verification failed"

#         success "API Ops Secret Manager verification successful"

#         disable_old_secret_versions \
#             "${secret_name}" \
#             "${GCP_PROJECT}"

#         #######################################################################
#         # INITIAL CREATION COMPLETE
#         #######################################################################

#         success "=============================================="
#         success "Initial API Ops token creation completed successfully"
#         success "=============================================="

#     fi
# }

# ###############################################################################
# # Platform Ops Rotation
# ###############################################################################

# wait_for_token_name_available() {
#     local auth_token="$1"
#     local system_account_id="$2"
#     local token_name="$3"

#     local max_attempts="${4:-15}"
#     local sleep_seconds="${5:-2}"

#     local attempt
#     local tokens_response
#     local matching_token_id

#     log "Waiting for Konnect to release token name: ${token_name}"

#     for ((attempt=1; attempt<=max_attempts; attempt++)); do

#         tokens_response="$(
#             curl -sS \
#                 --fail-with-body \
#                 -X GET \
#                 "${KONNECT_API_BASE}/system-accounts/${system_account_id}/access-tokens" \
#                 -H "Authorization: Bearer ${auth_token}" \
#                 -H "Content-Type: application/json" \
#                 2>/dev/null
#         )" || true

#         matching_token_id="$(
#             jq -r \
#                 --arg token_name "${token_name}" \
#                 '.data[]? | select(.name == $token_name) | .id' \
#                 <<< "${tokens_response}" \
#                 | head -n 1
#         )"

#         if [[ -z "${matching_token_id}" ]]; then
#             log "Token name is now available: ${token_name}"
#             return 0
#         fi

#         log "Attempt ${attempt}/${max_attempts}: token name still exists"
#         debug "Existing token ID using ${token_name}: ${matching_token_id}"

#         if (( attempt < max_attempts )); then
#             sleep "${sleep_seconds}"
#         fi
#     done

#     fail "Token name '${token_name}' is still occupied after ${max_attempts} attempts"
# }

# rotate_platform_ops() {
#     local secret_name="${PLATFORM_OPS_SECRET_NAME}"
#     local project="us-prod-itg-api-kong-01"

#     log "=============================================="
#     log "Starting Platform Ops token rotation"
#     log "=============================================="

#     local target_secret_json
#     local system_account_id
#     local old_token_id
#     local old_token
#     local auth_token
#     local temporary_token_name
#     local final_token_name
#     local expires_at

#     log "Fetching Platform Ops secret..."

#     target_secret_json="$(
#         fetch_secret \
#             "${secret_name}" \
#             "${project}"
#     )"

#     validate_secret_json \
#         "${target_secret_json}" \
#         "${secret_name}"

#     ###########################################################################
#     # Get Platform Ops system account ID
#     ###########################################################################

#     system_account_id="$(
#         get_system_account_id \
#             "${target_secret_json}" \
#             "${secret_name}"
#     )"

#     ###########################################################################
#     # Get existing token information
#     ###########################################################################

#     old_token_id="$(get_old_token_id "${target_secret_json}")"
#     old_token="$(get_old_token "${target_secret_json}")"

#     ###########################################################################
#     # Get authentication token
#     ###########################################################################

#     log "Fetching Konnect authentication token..."

#     auth_token="$(get_auth_token)"

#     [[ -n "${auth_token}" ]] ||
#         fail "Konnect authentication token was not retrieved"

#     debug "Authentication token retrieved successfully"
#     debug "Authentication token length: ${#auth_token}"
#     debug "Authentication token starts with: ${auth_token:0:8}..."

#     ###########################################################################
#     # Build Platform Ops token names
#     ###########################################################################

#     temporary_token_name="$(build_platform_ops_timestamped_token_name)"
#     final_token_name="$(build_platform_ops_final_token_name)"

#     expires_at="$(get_expiry_date)"

#     log "Secret Name       : ${secret_name}"
#     log "System Account ID : ${system_account_id}"
#     log "Temporary Name    : ${temporary_token_name}"
#     log "Final Token Name  : ${final_token_name}"
#     log "Expires At        : ${expires_at}"

#     ###########################################################################
#     # Create new token FIRST
#     ###########################################################################

#     log "Creating new Platform Ops token"

#     local created_token_json
#     local new_token_id
#     local new_token

#     created_token_json="$(
#         create_konnect_token \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${temporary_token_name}" \
#             "${expires_at}"
#     )"

#     new_token_id="$(
#         jq -r '.token_id // empty' <<< "${created_token_json}"
#     )"

#     new_token="$(
#         jq -r '.token // empty' <<< "${created_token_json}"
#     )"

#     [[ -n "${new_token_id}" ]] ||
#         fail "New Platform Ops token_id was not returned"

#     [[ -n "${new_token}" ]] ||
#         fail "New Platform Ops token was not returned"

#     log "New Platform Ops token created successfully"
#     log "New Token ID: ${new_token_id}"

#     ###########################################################################
#     # Update Secret Manager BEFORE deleting old token
#     ###########################################################################

#     local updated_secret_json

#     updated_secret_json="$(
#         build_updated_secret_json \
#             "${target_secret_json}" \
#             "${new_token_id}" \
#             "${new_token}" \
#             "${expires_at}"
#     )"

#     log "Updating Platform Ops Secret Manager secret"

#     add_secret_version \
#         "${secret_name}" \
#         "${updated_secret_json}" \
#         "${project}"

#     log "Platform Ops Secret Manager updated successfully"

#     ###########################################################################
#     # Verify Secret Manager
#     ###########################################################################

#     log "Verifying latest Platform Ops Secret Manager version"

#     local latest_secret_json
#     local latest_token_id

#     latest_secret_json="$(
#         fetch_secret \
#             "${secret_name}" \
#             "${project}"
#     )"

#     validate_secret_json \
#         "${latest_secret_json}" \
#         "${secret_name}"

#     latest_token_id="$(
#         jq -r '.token_id // empty' <<< "${latest_secret_json}"
#     )"

#     [[ "${latest_token_id}" == "${new_token_id}" ]] ||
#         fail "Platform Ops Secret Manager verification failed"

#     success "Platform Ops Secret Manager verification successful"

#     ###########################################################################
#     # Prepare temporary name for OLD Platform Ops token
#     ###########################################################################

#     local old_platform_ops_token_name

#     old_platform_ops_token_name="$(
#         printf '%s-old-%s' \
#             "${PLATFORM_OPS_TOKEN_BASE_NAME}" \
#             "$(date -u '+%Y%m%d%H%M%S')"
#     )"

#     ###########################################################################
#     # Rename OLD token temporarily
#     ###########################################################################

#     if [[ -n "${old_token_id}" && -n "${old_token}" ]]; then

#         log "Renaming old Platform Ops token temporarily"
#         log "Temporary old token name: ${old_platform_ops_token_name}"

#         rename_konnect_token \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${old_token_id}" \
#             "${old_platform_ops_token_name}"

#         success "Old Platform Ops token moved to temporary name"

#         wait_for_token_name_available \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${final_token_name}" \
#             15 \
#             2

#     else

#         log "No old Platform Ops token found"
#         log "Permanent token name should already be available"
#     fi

#     ###########################################################################
#     # Rename NEW token to the permanent Platform Ops token name
#     ###########################################################################

#     log "Renaming newly created Platform Ops token"
#     log "New token ID: ${new_token_id}"
#     log "Permanent token name: ${final_token_name}"

#     rename_konnect_token \
#         "${auth_token}" \
#         "${system_account_id}" \
#         "${new_token_id}" \
#         "${final_token_name}"

#     success "New Platform Ops token renamed successfully to: ${final_token_name}"

#     ###########################################################################
#     # Delete OLD token
#     ###########################################################################

#     if [[ -n "${old_token_id}" && -n "${old_token}" ]]; then

#         log "Deleting old Platform Ops token"

#         delete_konnect_token \
#             "${auth_token}" \
#             "${system_account_id}" \
#             "${old_token_id}"

#         success "Old Platform Ops token deleted successfully"

#     else

#         log "No old Platform Ops token found"
#         log "Skipping old token deletion"

#     fi

#     disable_old_secret_versions \
#         "${secret_name}" \
#         "${project}"

#     ###########################################################################
#     # Complete
#     ###########################################################################

#     success "=============================================="
#     success "Platform Ops token rotation completed successfully"
#     success "=============================================="
# }

# ###############################################################################
# # Main
# ###############################################################################

# main()
# {
#     ###########################################################################
#     # Validate arguments BEFORE prerequisites
#     ###########################################################################

#     if [[ $# -eq 0 ]]; then
#         echo "ERROR: No arguments provided." >&2
#         usage >&2
#         exit 1
#     fi

#     if [[ "$1" == "-h" || "$1" == "--help" ]]; then
#         usage
#         exit 0
#     fi

#     ###########################################################################
#     # Validate prerequisites
#     ###########################################################################

#     validate_prerequisites

#     ###########################################################################
#     # Initialize arguments
#     ###########################################################################

#     TOKEN_TYPE=""

#     ENV_NAME=""
#     CP_TYPE=""
#     TTL_DAYS=""

#     ###########################################################################
#     # Platform Ops
#     ###########################################################################

#     if [[ "$1" == "platform-ops" ]]; then

#         TOKEN_TYPE="platform-ops"

#         #######################################################################
#         # Platform Ops is ALWAYS PROD
#         #######################################################################

#         ENV_NAME="prd"
#         TTL_DAYS="${2:-${DEFAULT_TTL_DAYS}}"

#         if [[ $# -gt 2 ]]; then
#             fail "Too many arguments for Platform Ops rotation."
#         fi

#         validate_ttl "${TTL_DAYS}"

#         set_gcp_project

#         PLATFORM_OPS_SECRET_NAME="$(
#             build_platform_ops_secret_name "prd"
#         )"

#     ###########################################################################
#     # API Ops
#     ###########################################################################

#     elif [[ $# -eq 4 ]]; then

#         ENV_NAME="$1"
#         TOKEN_TYPE="$2"
#         TTL_DAYS="$3"
#         CP_TYPE="$4"

#         if [[ "${TOKEN_TYPE}" != "api-ops" ]]; then
#             fail "Invalid token type '${TOKEN_TYPE}'. Expected: api-ops"
#         fi

#         validate_api_environment "${ENV_NAME}"

#         validate_cp_type "${CP_TYPE}"

#         validate_ttl "${TTL_DAYS}"

#         #######################################################################
#         # API Ops target project remains environment-specific
#         #######################################################################

#         set_gcp_project

#         #######################################################################
#         # BUT Platform Ops authentication is ALWAYS PROD
#         #######################################################################

#         PLATFORM_OPS_SECRET_NAME="$(
#             build_platform_ops_secret_name "prod"
#         )"

#     ###########################################################################
#     # Invalid argument count
#     ###########################################################################

#     else

#         echo "ERROR: Invalid arguments." >&2
#         usage >&2
#         exit 1

#     fi

#     ###########################################################################
#     # Display configuration
#     ###########################################################################

#     set_gcp_project

#     log "=============================================="
#     log "Kong Konnect Token Rotation"
#     log "=============================================="

#     log "Token Type : ${TOKEN_TYPE}"
#     log "TTL Days   : ${TTL_DAYS}"
#     log "GCP Project: ${GCP_PROJECT}"
#     log "Konnect API: ${KONNECT_API_BASE}"

#     ###########################################################################
#     # Execute rotation
#     ###########################################################################

#     if [[ "${TOKEN_TYPE}" == "api-ops" ]]; then

#         log "Environment: ${ENV_NAME}"
#         log "CP Type    : ${CP_TYPE}"

#         local secret_name

#         secret_name="$(
#             build_api_ops_secret_name \
#                 "${ENV_NAME}" \
#                 "${CP_TYPE}"
#         )"

#         rotate_api_ops "${secret_name}"

#     else

#         log "Platform Ops Project: us-prod-itg-api-kong-01"
#         log "Secret Name: ${PLATFORM_OPS_SECRET_NAME}"

#         rotate_platform_ops

#     fi
# }

# main "$@"
