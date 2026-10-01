#!/bin/bash
set -euo pipefail

################################################################################
# Script Name : export_tf_output.sh
#
# Purpose:
#   This script:
#   1. Reads Terraform outputs for selected environment
#   2. Generates CP configuration metadata using temporary files
#   3. Uploads CP metadata to GCP Secret Manager
#   4. For ONPREM CP:
#        - Creates temporary cp_info.yml
#        - Copies cp_info.yml to Bitbucket DP repository
#        - Deletes the temporary cp_info.yml after copying
#        - Pushes changes to feature branch
#        - Creates Pull Request feature branch -> main if one does not exist
#
# Important:
#   - Environment-to-GCP-project resolution is handled by deploy.sh.
#   - The resolved environment project is passed as the third argument.
#   - SAT token fetching is handled by fetch_konnect_token.sh.
#   - SAT token project is always the PROD project.
#   - CP metadata is uploaded to the environment-specific GCP project.
#   - cp-config.yml is NOT stored in this repository.
#   - cp_info.yml is NOT stored permanently in this repository.
#   - Generated files are created under a temporary directory.
#
# Usage:
#   ./export_tf_output.sh <environment> <ONPREM|GCLOUD> <gcp-project-id>
#
# Example:
#   ./export_tf_output.sh ppd GCLOUD us-pprd-itg-api-kong-01
#
################################################################################

ENVIRONMENT="${1:-}"
CP_TYPE="${2:-}"
CP_TYPE="${CP_TYPE^^}"
METADATA_PROJECT_ID="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=console/colors.sh
source "${SCRIPT_DIR}/console/colors.sh"

# shellcheck source=common/fetch_konnect_token.sh
source "${SCRIPT_DIR}/common/fetch_konnect_token.sh"

BITBUCKET_WORKSPACE="oreillyauto"

################################################################################
# Metadata Project Configuration
#
# IMPORTANT:
#   deploy.sh resolves the environment-specific GCP project and passes it as
#   argument 3.
#
#   SAT authentication is separate and is ALWAYS handled by
#   fetch_konnect_token.sh using the PROD project.
#
################################################################################

METADATA_SECRET_PREFIX=""

################################################################################
# Temporary Files
################################################################################

TMP_ROOT=""
TMP_TF_CONFIG=""
TMP_CP_INFO=""
TMP_SECRET_FILE=""

################################################################################
# Logging
################################################################################

log_info() {
    printf '%s[INFO]%s %s\n' \
        "${COLOR_BLUE}" \
        "${COLOR_RESET}" \
        "$*"
}

log_success() {
    printf '%s[SUCCESS]%s %s\n' \
        "${COLOR_GREEN}" \
        "${COLOR_RESET}" \
        "$*"
}

log_error() {
    printf '%s[ERROR]%s %s\n' \
        "${COLOR_RED}" \
        "${COLOR_RESET}" \
        "$*" >&2
}

log_skip() {
    printf '%s[SKIP]%s %s\n' \
        "${COLOR_YELLOW}" \
        "${COLOR_RESET}" \
        "$*"
}

log_secret() {
    printf '%s[SECRET]%s %s%s%s\n' \
        "${COLOR_BOLD}${COLOR_CYAN}" \
        "${COLOR_RESET}" \
        "${COLOR_BOLD}" \
        "$*" \
        "${COLOR_RESET}"
}

print_banner() {

    local title="$1"
    local color="$2"

    printf '\n%s================================================%s\n' \
        "${color}${COLOR_BOLD}" \
        "${COLOR_RESET}"

    printf '%s %s%s\n' \
        "${color}${COLOR_BOLD}" \
        "${title}" \
        "${COLOR_RESET}"

    printf '%s================================================%s\n' \
        "${color}${COLOR_BOLD}" \
        "${COLOR_RESET}"
}

################################################################################
# Function : validate_inputs
################################################################################

validate_inputs() {

    log_info 'Validating script inputs...'

    if [[ -z "${ENVIRONMENT}" ||
          -z "${CP_TYPE}" ||
          -z "${METADATA_PROJECT_ID}" ]]; then

        log_error 'Missing required parameters.'

        printf '%sUsage: %s <environment> <ONPREM|GCLOUD> <gcp-project-id>%s\n' \
            "${COLOR_YELLOW}" \
            "$0" \
            "${COLOR_RESET}" >&2

        exit 1
    fi

    ENVIRONMENT="${ENVIRONMENT,,}"

    case "${ENVIRONMENT}" in
        dev|uat|ppd|prd)
            ;;
        *)
            log_error "Invalid environment: ${ENVIRONMENT}"
            exit 1
            ;;
    esac

    case "${CP_TYPE}" in
        ONPREM|GCLOUD)
            ;;
        *)
            log_error "Invalid CP_TYPE: ${CP_TYPE}"
            exit 1
            ;;
    esac

    # The project must be supplied by deploy.sh.
    if [[ -z "${METADATA_PROJECT_ID}" ]]; then
        log_error 'Metadata GCP project was not provided by deploy.sh.'
        exit 1
    fi

    # Derive the secret prefix from the resolved project ID.
    METADATA_SECRET_PREFIX="${METADATA_PROJECT_ID%-01}"

    export METADATA_PROJECT_ID
    export METADATA_SECRET_PREFIX

    log_success "Environment : ${ENVIRONMENT}"
    log_success "CP Type     : ${CP_TYPE}"
    log_info "Metadata GCP Project   : ${METADATA_PROJECT_ID}"
    log_info "Metadata Secret Prefix : ${METADATA_SECRET_PREFIX}"
}

################################################################################
# Function : setup_paths
#
# Determines:
#   - Terraform directory
#   - CP metadata secret name
#
# IMPORTANT:
# Secret names are derived from METADATA_SECRET_PREFIX, NOT ENVIRONMENT.
#
################################################################################

setup_paths() {

    log_info 'Setting Terraform paths...'

    case "${CP_TYPE}" in

        ONPREM)

            log_info 'Processing ONPREM Control Plane'

            PROJECT_DIR="${REPO_ROOT}/env/${ENVIRONMENT}/onprem-cp"

            SECRET_NAME="${METADATA_SECRET_PREFIX}-konnect-onprem-cp-info-${ENVIRONMENT}"

            ;;

        GCLOUD)

            log_info 'Processing GCLOUD Control Plane'

            PROJECT_DIR="${REPO_ROOT}/env/${ENVIRONMENT}/gcloud-cp"

            SECRET_NAME="${METADATA_SECRET_PREFIX}-konnect-gcloud-cp-info-${ENVIRONMENT}"

            ;;

        *)

            log_error "Invalid CP_TYPE ${CP_TYPE}"

            exit 1

            ;;
    esac

    if [[ ! -d "${PROJECT_DIR}" ]]; then

        log_error "Terraform directory does not exist: ${PROJECT_DIR}"

        exit 1
    fi

    TFVARS_FILE="${REPO_ROOT}/env/${ENVIRONMENT}/$(printf '%s' "${CP_TYPE}" | tr '[:upper:]' '[:lower:]')-cp/terraform.tfvars"

    if [[ ! -f "${TFVARS_FILE}" ]]; then
        log_error "Terraform variables file does not exist: ${TFVARS_FILE}"
        exit 1
    fi

    log_info "Terraform Directory : ${PROJECT_DIR}"
    log_secret "Secret Name         : ${SECRET_NAME}"
    log_info "Metadata Project     : ${METADATA_PROJECT_ID}"
}

################################################################################
# Function : initialize_temp_files
################################################################################

initialize_temp_files() {

    TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kong-konnect-metadata.XXXXXX")"

    TMP_TF_CONFIG="${TMP_ROOT}/cp-config.yml"
    TMP_CP_INFO="${TMP_ROOT}/cp_info.yml"
    TMP_SECRET_FILE="${TMP_ROOT}/secret.json"

    log_info "Temporary working directory created."
}

################################################################################
# Function : fetch_tf_outputs
################################################################################

fetch_tf_outputs() {

    log_info 'Fetching Terraform outputs...'

    TF_JSON=$(terraform \
        -chdir="${PROJECT_DIR}" \
        output -json)

    TF_SYSTEM_ACCOUNT_ID=$(printf '%s\n' "${TF_JSON}" \
        | jq -r '.system_account_id.value // empty')

    if [[ -z "${TF_SYSTEM_ACCOUNT_ID}" ]]; then

        log_error 'Unable to fetch system_account_id'

        exit 1
    fi

    terraform \
        -chdir="${PROJECT_DIR}" \
        output -raw cp_config_yaml \
        > "${TMP_TF_CONFIG}"

    if [[ ! -s "${TMP_TF_CONFIG}" ]]; then

        log_error 'Terraform cp_config_yaml output is empty.'

        exit 1
    fi

    log_success 'Terraform outputs fetched.'
}

################################################################################
# Function : extract_endpoint
################################################################################

extract_endpoint() {

    local endpoint_name="$1"

    grep "${endpoint_name}" "${TMP_TF_CONFIG}" \
        | sed -E 's/.*"([^"]+)".*/\1/' \
        | sed -E 's#https://##;s/:443$//'
}

################################################################################
# Function : generate_cp_info
################################################################################

generate_cp_info() {

    log_info 'Preparing temporary CP configuration...'

    CONTROL_PLANE_ENDPOINT="$(extract_endpoint control_plane_endpoint)"
    TELEMETRY_ENDPOINT="$(extract_endpoint telemetry_endpoint)"

    if [[ -z "${CONTROL_PLANE_ENDPOINT}" ]]; then

        log_error 'Unable to extract control_plane_endpoint.'

        exit 1
    fi

    if [[ -z "${TELEMETRY_ENDPOINT}" ]]; then

        log_error 'Unable to extract telemetry_endpoint.'

        exit 1
    fi

    cat > "${TMP_CP_INFO}" <<EOF
control_plane_endpoint: "${CONTROL_PLANE_ENDPOINT}"
telemetry_endpoint: "${TELEMETRY_ENDPOINT}"
EOF

    log_success 'Temporary cp_info.yml generated.'
    log_success "Control Plane Endpoint : ${CONTROL_PLANE_ENDPOINT}"
    log_success "Telemetry Endpoint     : ${TELEMETRY_ENDPOINT}"
}

################################################################################
# Function : preserve_existing_token_data
################################################################################

preserve_existing_token_data() {

    local existing_secret_json="$1"
    local new_secret_json="$2"

    jq -n \
        --argjson existing "${existing_secret_json}" \
        --argjson new "${new_secret_json}" \
        '
        $new

        | if ($existing.token_id // "") != "" then
              .token_id = $existing.token_id
          else
              .
          end

        | if ($existing.token // "") != "" then
              .token = $existing.token
          else
              .
          end
    ' \
        <(printf '%s\n' "${existing_secret_json}") \
        <(printf '%s\n' "${new_secret_json}")
}

################################################################################
# Function : upload_secret
################################################################################

upload_secret() {

    local SECRET_NAME="$1"
    local CURRENT_SECRET_FILE="${TMP_ROOT}/current-secret.json"
    local EXISTING_SECRET_JSON=""
    local NEW_SECRET_JSON=""
    local GCLOUD_OUTPUT=""
    local GCLOUD_STATUS=0

    log_info "Updating Secret Manager secret: ${SECRET_NAME}"
    log_info "Metadata project: ${METADATA_PROJECT_ID}"

    ############################################################################
    # Validate Secret
    ############################################################################

    if ! gcloud secrets describe "${SECRET_NAME}" \
        --project="${METADATA_PROJECT_ID}" >/dev/null 2>&1; then

        log_error \
            "Secret ${SECRET_NAME} does not exist in project ${METADATA_PROJECT_ID}."

        return 1
    fi

    ############################################################################
    # Create New CP Metadata
    ############################################################################

    NEW_SECRET_JSON="$(
        jq -n \
            --arg system_account_id "${TF_SYSTEM_ACCOUNT_ID}" \
            --arg control_plane_endpoint "${CONTROL_PLANE_ENDPOINT}" \
            --arg telemetry_endpoint "${TELEMETRY_ENDPOINT}" \
            '{
                system_account_id: $system_account_id,
                control_plane_endpoint: $control_plane_endpoint,
                telemetry_endpoint: $telemetry_endpoint
            }'
    )"

    ############################################################################
    # Preserve Existing Token Information
    ############################################################################

    if EXISTING_SECRET_JSON="$(
        gcloud secrets versions access latest \
            --secret="${SECRET_NAME}" \
            --project="${METADATA_PROJECT_ID}" \
            2>/dev/null
    )"; then

        log_info "Existing CP-info secret found."

        NEW_SECRET_JSON="$(
            preserve_existing_token_data \
                "${EXISTING_SECRET_JSON}" \
                "${NEW_SECRET_JSON}"
        )"

        log_success "Existing token_id and token preserved."

    else

        log_info \
            "No existing CP-info secret version found. Creating initial secret."
    fi

    ############################################################################
    # Validate Generated JSON
    ############################################################################

    if ! printf '%s\n' "${NEW_SECRET_JSON}" | jq empty >/dev/null 2>&1; then

        log_error "Generated CP metadata is not valid JSON."

        return 1
    fi

    ############################################################################
    # Write Final Secret File
    ############################################################################

    printf '%s\n' "${NEW_SECRET_JSON}" > "${TMP_SECRET_FILE}"

    if [[ ! -s "${TMP_SECRET_FILE}" ]]; then

        log_error \
            "Secret file is empty or was not created: ${TMP_SECRET_FILE}"

        return 1
    fi

    ############################################################################
    # Compare with Existing Version
    ############################################################################

    if gcloud secrets versions access latest \
        --secret="${SECRET_NAME}" \
        --project="${METADATA_PROJECT_ID}" \
        --out-file="${CURRENT_SECRET_FILE}" \
        >/dev/null 2>&1; then

        if cmp -s "${TMP_SECRET_FILE}" "${CURRENT_SECRET_FILE}"; then

            log_skip \
                "Secret content unchanged. No new version created."

            return 0
        fi
    fi

    ############################################################################
    # Create New Secret Version
    ############################################################################

    GCLOUD_OUTPUT="$(
        gcloud secrets versions add "${SECRET_NAME}" \
            --data-file="${TMP_SECRET_FILE}" \
            --project="${METADATA_PROJECT_ID}" \
            2>&1
    )"

    GCLOUD_STATUS=$?

    while IFS= read -r line; do

        if [[ "${line}" == Created\ version* ]]; then

            printf '%s%s%s\n' \
                "${COLOR_GREEN}" \
                "${line}" \
                "${COLOR_RESET}"

        else

            printf '%s\n' "${line}"

        fi

    done <<< "${GCLOUD_OUTPUT}"

    if [[ "${GCLOUD_STATUS}" -ne 0 ]]; then

        log_error "Failed to create new Secret Manager version."

        return 1
    fi

    log_success \
        "Secret ${SECRET_NAME} updated successfully in ${METADATA_PROJECT_ID}."

    return 0
}

################################################################################
# Function : update_onprem_repo
################################################################################

update_onprem_repo() {

    local REPO="kong-onprem-dp-itg"
    local WORK_DIR="/tmp/${REPO}"
    local TARGET_FILE="inventory/${ENVIRONMENT}/cp_info.yml"
    local TARGET_BRANCH="main"
    local TIMESTAMP
    local SOURCE_BRANCH

    TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
    SOURCE_BRANCH="feature-branch-${TIMESTAMP}"

    log_info "Updating repository: ${REPO}"
    log_info "Target branch : ${TARGET_BRANCH}"
    log_info "Feature branch: ${SOURCE_BRANCH}"

    rm -rf "${WORK_DIR}"

    log_info "Cloning Bitbucket repository..."

    git clone \
        "git@bitbucket.org:${BITBUCKET_WORKSPACE}/${REPO}.git" \
        "${WORK_DIR}" > /dev/null 2>&1 || {

        log_error "Failed to clone Bitbucket repository."
        exit 1
    }

    cd "${WORK_DIR}" || {

        log_error "Failed to access repository directory."
        exit 1
    }

    log_info "Fetching latest ${TARGET_BRANCH} branch..."

    git fetch origin "${TARGET_BRANCH}" >/dev/null 2>&1 || {

        log_error "Failed to fetch ${TARGET_BRANCH} branch."
        exit 1
    }

    log_info "Checking out ${TARGET_BRANCH}..."

    git checkout "${TARGET_BRANCH}" >/dev/null 2>&1 || {

        log_error "Failed to checkout ${TARGET_BRANCH} branch."
        exit 1
    }

    log_info "Pulling latest changes from ${TARGET_BRANCH}..."

    git pull \
        --ff-only \
        origin "${TARGET_BRANCH}" >/dev/null 2>&1 || {

        log_error "Failed to pull latest ${TARGET_BRANCH}."
        exit 1
    }

    log_info "Creating feature branch ${SOURCE_BRANCH}..."

    git checkout -b "${SOURCE_BRANCH}" >/dev/null 2>&1 || {

        log_error \
            "Failed to create feature branch ${SOURCE_BRANCH}."
        exit 1
    }

    log_success \
        "Created feature branch ${SOURCE_BRANCH} from latest ${TARGET_BRANCH}."

    mkdir -p "inventory/${ENVIRONMENT}"

    log_info "Copying temporary cp_info.yml to DP repository..."

    cp \
        "${TMP_CP_INFO}" \
        "${WORK_DIR}/${TARGET_FILE}" || {

        log_error "Failed to copy cp_info.yml to repository."
        exit 1
    }

    rm -f "${TMP_CP_INFO}"

    log_info "Temporary cp_info.yml removed."
    log_info "CP metadata copied to ${TARGET_FILE}"

    git config user.name "$(whoami)"
    git config user.email "${BITBUCKET_USERNAME}"

    git add "${TARGET_FILE}" || {

        log_error "Failed to stage ${TARGET_FILE}."
        exit 1
    }

    if git diff --cached --quiet; then

        log_skip 'No changes detected. Nothing to commit.'

        return 0
    fi

    git commit \
        -m "Update cp_info.yml for ${ENVIRONMENT}" || {

        log_error "Failed to create Git commit."
        exit 1
    }

    log_info "Pushing feature branch ${SOURCE_BRANCH}..."

    git push \
        -u \
        origin "${SOURCE_BRANCH}" || {

        log_error \
            "Failed to push feature branch ${SOURCE_BRANCH}."
        exit 1
    }

    log_success "Feature branch pushed successfully."

    create_pr \
        "${REPO}" \
        "${SOURCE_BRANCH}" \
        "${TARGET_BRANCH}"
}

################################################################################
# Function : create_pr
################################################################################

create_pr() {

    local REPO_SLUG="$1"
    local SOURCE_BRANCH="$2"
    local TARGET_BRANCH="$3"

    if [[ -z "${BITBUCKET_USERNAME:-}" ||
          -z "${BITBUCKET_TOKEN:-}" ]]; then

        log_error 'BITBUCKET_USERNAME or BITBUCKET_TOKEN is not set.'
        exit 1
    fi

    if ! command -v jq >/dev/null 2>&1; then

        log_error 'jq is required but not installed.'
        exit 1
    fi

    local PR_URL
    local PR_RESPONSE
    local EXISTING_PR

    PR_URL="https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${REPO_SLUG}/pullrequests"

    print_banner \
        'Checking existing Pull Requests...' \
        "${COLOR_BLUE}"

    log_info "Workspace      : ${BITBUCKET_WORKSPACE}"
    log_info "Repo           : ${REPO_SLUG}"
    log_info "Source branch  : ${SOURCE_BRANCH}"
    log_info "Target branch  : ${TARGET_BRANCH}"

    PR_RESPONSE=$(curl \
        --silent \
        --show-error \
        --fail \
        -u "${BITBUCKET_USERNAME}:${BITBUCKET_TOKEN}" \
        "${PR_URL}?state=OPEN") || {

        log_error "Failed to query Bitbucket Pull Requests."
        exit 1
    }

    EXISTING_PR=$(printf '%s\n' "${PR_RESPONSE}" | jq -r \
        --arg SOURCE "${SOURCE_BRANCH}" \
        --arg TARGET "${TARGET_BRANCH}" '

[
    .values[]
    |
    select(
        .source.branch.name == $SOURCE
        and
        .destination.branch.name == $TARGET
    )
]
| length
')

    log_info "Existing PR count : ${EXISTING_PR}"

    if [[ "${EXISTING_PR}" -gt 0 ]]; then

        log_info \
            "Pull Request ${SOURCE_BRANCH} -> ${TARGET_BRANCH} already exists."

        return 0
    fi

    print_banner \
        'Creating Pull Request...' \
        "${COLOR_BLUE}"

    if curl \
        --connect-timeout 10 \
        --max-time 30 \
        --silent \
        --show-error \
        --fail \
        --output /dev/null \
        -u "${BITBUCKET_USERNAME}:${BITBUCKET_TOKEN}" \
        -H "Content-Type: application/json" \
        -X POST \
        "${PR_URL}" \
        -d @- <<EOF
{
  "title": "Update cp_info.yml for ${ENVIRONMENT}",
  "description": "Automated update of cp_info.yml for the ${ENVIRONMENT} environment.",
  "source": {
    "branch": {
      "name": "${SOURCE_BRANCH}"
    }
  },
  "destination": {
    "branch": {
      "name": "${TARGET_BRANCH}"
    }
  },
  "close_source_branch": false
}
EOF
    then

        log_success \
            "Pull Request ${SOURCE_BRANCH} -> ${TARGET_BRANCH} created successfully."

    else

        log_error "Failed to create Pull Request."
        exit 1
    fi
}

################################################################################
# Main execution flow
################################################################################

main() {

    print_banner \
        'Starting CP Metadata Automation' \
        "${COLOR_BLUE}"

    validate_inputs

    setup_paths

    initialize_temp_files

    fetch_tf_outputs

    generate_cp_info

    case "${CP_TYPE}" in

        ONPREM)

            log_info 'Uploading ONPREM metadata'

            upload_secret "${SECRET_NAME}"

            update_onprem_repo

            ;;

        GCLOUD)

            log_info 'Uploading GCLOUD metadata'

            upload_secret "${SECRET_NAME}"

            ;;

    esac

    print_banner \
        'Automation completed successfully' \
        "${COLOR_GREEN}"
}

################################################################################
# Cleanup
################################################################################

cleanup() {

    if [[ -n "${TMP_ROOT:-}" && -d "${TMP_ROOT}" ]]; then

        rm -rf "${TMP_ROOT}"
    fi
}

trap cleanup EXIT

main