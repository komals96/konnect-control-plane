#!/bin/bash
set -euo pipefail

################################################################################
# Script Name : validate_prerequisites.sh
#
# Purpose:
#   Validate prerequisites required to execute the Konnect automation.
#
# Usage:
#   ./validate_prerequisites.sh <environment> <ONPREM|GCLOUD>
#
# Examples:
#   ./validate_prerequisites.sh dev ONPREM
#   ./validate_prerequisites.sh ppd GCLOUD
#
################################################################################

ENVIRONMENT="${1:-}"
CP_TYPE="${2:-}"

CP_TYPE="${CP_TYPE^^}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../console/colors.sh
source "${SCRIPTS_DIR}/console/colors.sh"


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


################################################################################
# Usage
################################################################################

usage() {
    cat <<EOF

Usage:
  $0 <environment> <ONPREM|GCLOUD>

Examples:
  $0 dev ONPREM
  $0 ppd GCLOUD

Supported environments:
  dev
  uat
  ppd
  prd

Supported control planes:
  ONPREM
  GCLOUD

EOF
}


################################################################################
# Validate Arguments
################################################################################

if [[ -z "${ENVIRONMENT}" || -z "${CP_TYPE}" ]]; then
    log_error "Environment and Control Plane type are required."
    usage
    exit 1
fi

ENVIRONMENT="${ENVIRONMENT,,}"

case "${ENVIRONMENT}" in
    dev|uat|ppd|prd)
        ;;
    *)
        log_error "Invalid environment: ${ENVIRONMENT}"
        usage
        exit 1
        ;;
esac

case "${CP_TYPE}" in
    ONPREM|GCLOUD)
        ;;
    *)
        log_error "Invalid Control Plane type: ${CP_TYPE}"
        usage
        exit 1
        ;;
esac


################################################################################
# Configuration
################################################################################
#
# Do not construct these names directly from ENVIRONMENT.
# DEV uses nprd and PPD uses pprd in the GCP resource naming.
#
################################################################################

case "${ENVIRONMENT}" in

    dev|uat)
        GCP_PROJECT="us-nprd-itg-api-kong-01"
        GCP_BUCKET="us-nprd-itg-api-kong-tfstate"
        SECRET_NAME="us-nprd-itg-api-kong-konnect-platform-ops-sat-info"
        ;;

    ppd)
        GCP_PROJECT="us-pprd-itg-api-kong-01"
        GCP_BUCKET="us-pprd-itg-api-kong-tfstate"
        SECRET_NAME="us-pprd-itg-api-kong-konnect-platform-ops-sat-info"
        ;;

    prd)
        GCP_PROJECT="us-prod-itg-api-kong-01"
        GCP_BUCKET="us-prod-itg-api-kong-tfstate"
        SECRET_NAME="us-prod-itg-api-kong-konnect-platform-ops-sat-info"
        ;;

esac


case "${CP_TYPE}" in
    ONPREM)
        GCP_PREFIX="onprem/${ENVIRONMENT}/control-plane"
        ;;
    GCLOUD)
        GCP_PREFIX="gcloud/${ENVIRONMENT}/control-plane"
        ;;
esac


################################################################################
# Terraform Configuration
################################################################################

CP_TYPE_LOWER="$(printf '%s' "${CP_TYPE}" | tr '[:upper:]' '[:lower:]')"

TERRAFORM_DIR="${REPO_ROOT}/env/${ENVIRONMENT}/${CP_TYPE_LOWER}-cp"
TFVARS_FILE="${TERRAFORM_DIR}/terraform.tfvars"


################################################################################
# Counters
################################################################################

PASSED_CHECKS=0
FAILED_CHECKS=0


################################################################################
# Banner
################################################################################

echo
printf '%s\n' \
    "======================================================================"
printf '%s\n' \
    "                 KONNECT PREREQUISITE VALIDATION"
printf '%s\n' \
    "======================================================================"

printf 'Environment      : %s\n' "${ENVIRONMENT^^}"
printf 'Control Plane    : %s\n' "${CP_TYPE}"
printf 'GCP Project      : %s\n' "${GCP_PROJECT}"
printf 'GCS Bucket       : %s\n' "${GCP_BUCKET}"
printf 'GCS Prefix       : %s\n' "${GCP_PREFIX}"
printf 'Secret           : %s\n' "${SECRET_NAME}"

printf '%s\n' \
    "======================================================================"

echo


################################################################################
# 1. Required Tools
################################################################################

printf '[1/5] Required tools\n'

REQUIRED_TOOLS=(
    bash
    terraform
    gcloud
    curl
    git
    jq
)

TOOLS_VALID=true
MISSING_TOOLS=()

for tool in "${REQUIRED_TOOLS[@]}"; do

    if command -v "${tool}" >/dev/null 2>&1; then

        printf '      %s✔ %s%s\n' \
            "${COLOR_GREEN}" \
            "${tool}" \
            "${COLOR_RESET}"

    else

        TOOLS_VALID=false
        MISSING_TOOLS+=("${tool}")

        printf '      %s✘ %s%s\n' \
            "${COLOR_RED}" \
            "${tool}" \
            "${COLOR_RESET}"

    fi

done

if [[ "${TOOLS_VALID}" == true ]]; then

    PASSED_CHECKS=$((PASSED_CHECKS + 1))

else

    FAILED_CHECKS=$((FAILED_CHECKS + 1))

    log_error "Missing required tool(s): ${MISSING_TOOLS[*]}"

fi

echo


################################################################################
# 2. GCP Authentication and Project Access
################################################################################

printf '[2/5] GCP authentication and project access\n'

GCP_VALID=true

if ! gcloud auth list \
        --filter="status:ACTIVE" \
        --format="value(account)" \
        >/dev/null 2>&1; then
    GCP_VALID=false
fi

if [[ "${GCP_VALID}" == true ]]; then
    if ! gcloud projects describe "${GCP_PROJECT}" \
            --format="value(projectId)" \
            >/dev/null 2>&1; then
        GCP_VALID=false
    fi
fi

if [[ "${GCP_VALID}" == true ]]; then

    PASSED_CHECKS=$((PASSED_CHECKS + 1))

    printf '      %s✔ Active GCP authentication%s\n' \
        "${COLOR_GREEN}" "${COLOR_RESET}"

    printf '      %s✔ Project access: %s%s\n' \
        "${COLOR_GREEN}" \
        "${GCP_PROJECT}" \
        "${COLOR_RESET}"

else

    FAILED_CHECKS=$((FAILED_CHECKS + 1))

    printf '      %s✘ FAIL%s\n' \
        "${COLOR_RED}" \
        "${COLOR_RESET}"

    log_error "GCP authentication or project access failed."

fi

echo


################################################################################
# 3. GCS Terraform State Access
################################################################################

printf '[3/5] GCS Terraform state access\n'

if gcloud storage buckets describe \
        "gs://${GCP_BUCKET}" \
        --project="${GCP_PROJECT}" \
        >/dev/null 2>&1; then

    PASSED_CHECKS=$((PASSED_CHECKS + 1))

    printf '      %s✔ Bucket access: %s%s\n' \
        "${COLOR_GREEN}" \
        "${GCP_BUCKET}" \
        "${COLOR_RESET}"

    printf '      %s✔ Terraform state prefix: %s%s\n' \
        "${COLOR_GREEN}" \
        "${GCP_PREFIX}" \
        "${COLOR_RESET}"

else

    FAILED_CHECKS=$((FAILED_CHECKS + 1))

    printf '      %s✘ FAIL%s\n' \
        "${COLOR_RED}" \
        "${COLOR_RESET}"

    log_error "Unable to access GCS bucket: ${GCP_BUCKET}"

fi

echo


################################################################################
# 4. Secret Manager Access
################################################################################

printf '[4/5] Secret Manager access\n'

SECRET_ACCESS=true

if ! gcloud secrets describe "${SECRET_NAME}" \
        --project="${GCP_PROJECT}" \
        >/dev/null 2>&1; then

    SECRET_ACCESS=false

fi

if [[ "${SECRET_ACCESS}" == true ]]; then

    if ! gcloud secrets versions access latest \
            --secret="${SECRET_NAME}" \
            --project="${GCP_PROJECT}" \
            >/dev/null 2>&1; then

        SECRET_ACCESS=false

    fi

fi

if [[ "${SECRET_ACCESS}" == true ]]; then

    PASSED_CHECKS=$((PASSED_CHECKS + 1))

    printf '      %s✔ Secret exists: %s%s\n' \
        "${COLOR_GREEN}" \
        "${SECRET_NAME}" \
        "${COLOR_RESET}"

    printf '      %s✔ Secret read access%s\n' \
        "${COLOR_GREEN}" \
        "${COLOR_RESET}"

else

    FAILED_CHECKS=$((FAILED_CHECKS + 1))

    printf '      %s✘ FAIL%s\n' \
        "${COLOR_RED}" \
        "${COLOR_RESET}"

    log_error "Unable to access Secret Manager secret: ${SECRET_NAME}"

fi

echo


################################################################################
# Final Summary
################################################################################

printf '%s\n' \
    "======================================================================"
printf '%s\n' \
    "                 VALIDATION SUMMARY"
printf '%s\n' \
    "======================================================================"

printf 'Passed           : %s\n' "${PASSED_CHECKS}"
printf 'Failed           : %s\n' "${FAILED_CHECKS}"

echo

if [[ "${FAILED_CHECKS}" -gt 0 ]]; then

    printf 'Overall Status   : %sFAIL%s\n' \
        "${COLOR_RED}" \
        "${COLOR_RESET}"

    printf '%s\n' \
        "======================================================================"

    exit 1

fi

printf 'Overall Status   : %sPASS%s\n' \
    "${COLOR_GREEN}" \
    "${COLOR_RESET}"

printf '%s\n' \
    "======================================================================"

exit 0