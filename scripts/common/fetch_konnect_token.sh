#!/usr/bin/env bash
# Shared Konnect environment and SAT-token helpers.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Always use PROD project for SAT token
KONNECT_PROJECT_ID_SAT="us-prod-itg-api-kong-01"
SAT_SECRET_NAME="us-prod-itg-api-kong-konnect-platform-ops-sat-info"

# shellcheck source=../console/colors.sh
source "${SCRIPTS_DIR}/console/colors.sh"

################################################################################
# Logging
################################################################################

log_info() {
    printf '%s[INFO]%s %s\n' "${COLOR_BLUE}" "${COLOR_RESET}" "$*"
}

log_success() {
    printf '%s[SUCCESS]%s %s\n' "${COLOR_GREEN}" "${COLOR_RESET}" "$*"
}

log_error() {
    printf '%s[ERROR]%s %s\n' "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2
}

################################################################################
# Fetch Konnect SAT Token (always from PROD)
################################################################################

fetch_konnect_token() {

    # The Konnect SAT is a global authentication credential and is ALWAYS
    # retrieved from the PROD Secret Manager project/secret.
    # Target environment is intentionally not used for SAT lookup.

    # If pipeline already exported token, reuse it
    if [[ -n "${KONNECT_TOKEN:-}" ]]; then
        log_info "Reusing Konnect SAT token retrieved by pipeline."
        return 0
    fi

    log_info "Fetching Konnect SAT token from Secret Manager..."
    log_info "Project: ${KONNECT_PROJECT_ID_SAT}"
    log_info "Secret: ${SAT_SECRET_NAME}"

    local secret_value

    if ! secret_value="$(gcloud secrets versions access latest \
        --secret="${SAT_SECRET_NAME}" \
        --project="${KONNECT_PROJECT_ID_SAT}")"; then

        log_error "Failed to retrieve Konnect SAT token."
        log_error "Secret: ${SAT_SECRET_NAME}"
        log_error "Project: ${KONNECT_PROJECT_ID_SAT}"
        return 1
    fi

    # Extract token JSON field
    if ! KONNECT_TOKEN="$(printf '%s' "${secret_value}" | jq -r '.token // empty')"; then
        log_error "Failed to parse SAT secret JSON."
        return 1
    fi

    if [[ -z "${KONNECT_TOKEN}" ]]; then
        log_error "SAT token is missing or empty in secret: ${SAT_SECRET_NAME}"
        return 1
    fi

    export KONNECT_TOKEN
    log_success "Konnect SAT token retrieved successfully."
    return 0
}
