#!/bin/bash
set -euo pipefail

################################################################################
# Script Name : destroy_konnect_resources.sh
#
# Purpose:
#   Destroy Terraform-managed Konnect resources for a specific environment
#   and Control Plane type using the configured remote Terraform backend.
#
# Usage:
#   ./destroy_konnect_resources.sh <environment> <ONPREM|GCLOUD>
#
# Examples:
#   ./destroy_konnect_resources.sh dev ONPREM
#   ./destroy_konnect_resources.sh dev GCLOUD
#
################################################################################

ENVIRONMENT="${1:-}"
CP_TYPE="${2:-}"

CP_TYPE="${CP_TYPE^^}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=console/colors.sh
source "${SCRIPT_DIR}/console/colors.sh"

# shellcheck source=common/fetch_konnect_token.sh
source "${SCRIPT_DIR}/common/fetch_konnect_token.sh"


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

log_warning() {
    printf '%s[WARNING]%s %s\n' \
        "${COLOR_YELLOW}" \
        "${COLOR_RESET}" \
        "$*"
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
  $0 dev GCLOUD

Supported environments:
  dev
  uat
  ppd
  prod

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
    dev|uat|ppd|prod)
        ;;
    *)
        log_error "Invalid environment: ${ENVIRONMENT}"
        log_error "Supported environments: dev, ppd, prod"
        exit 1
        ;;
esac

case "${CP_TYPE}" in
    ONPREM|GCLOUD)
        ;;
    *)
        log_error "Invalid Control Plane type: ${CP_TYPE}"
        log_error "Supported values: ONPREM, GCLOUD"
        exit 1
        ;;
esac


################################################################################
# Terraform Configuration
################################################################################

CP_TYPE_LOWER="$(printf '%s' "${CP_TYPE}" | tr '[:upper:]' '[:lower:]')"

# The control-plane directory itself contains the Terraform configuration.
#
# Example:
#   env/ppd/gcloud-cp/
#       ├── *.tf
#       ├── terraform.tfvars
#       └── .terraform/
#
# .terraform is Terraform's local working directory and must NOT be used
# as the Terraform configuration directory.
TERRAFORM_DIR="${REPO_ROOT}/env/${ENVIRONMENT}/${CP_TYPE_LOWER}-cp"

TFVARS_FILE="${TERRAFORM_DIR}/terraform.tfvars"

TERRAFORM_LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kong-konnect-destroy.XXXXXX")"

TERRAFORM_INIT_LOG="${TERRAFORM_LOG_DIR}/terraform-init.log"
TERRAFORM_STATE_LOG="${TERRAFORM_LOG_DIR}/terraform-state.log"
DESTROY_PLAN="${TERRAFORM_LOG_DIR}/destroy.tfplan"
DESTROY_PLAN_LOG="${TERRAFORM_LOG_DIR}/destroy-plan.log"
DESTROY_SHOW_LOG="${TERRAFORM_LOG_DIR}/destroy-show.log"
DESTROY_LOG="${TERRAFORM_LOG_DIR}/destroy.log"


################################################################################
# Cleanup
################################################################################

cleanup() {
    if [[ -n "${TERRAFORM_LOG_DIR:-}" &&
          -d "${TERRAFORM_LOG_DIR}" ]]; then
        rm -rf "${TERRAFORM_LOG_DIR}"
    fi
}

trap cleanup EXIT


################################################################################
# Validate Terraform Configuration
################################################################################

if [[ ! -d "${TERRAFORM_DIR}" ]]; then
    log_error "Terraform configuration directory not found:"
    log_error "${TERRAFORM_DIR}"
    exit 1
fi

if [[ ! -f "${TFVARS_FILE}" ]]; then
    log_error "Terraform variables file not found:"
    log_error "${TFVARS_FILE}"
    exit 1
fi

if ! find "${TERRAFORM_DIR}" -maxdepth 1 -type f -name "*.tf" \
        | grep -q .; then
    log_error "No Terraform configuration files (*.tf) found:"
    log_error "${TERRAFORM_DIR}"
    exit 1
fi


################################################################################
# Display Execution Information
################################################################################

echo
printf '%s\n' \
    "======================================================================"
printf '%s\n' \
    "                 KONNECT RESOURCE DESTRUCTION"
printf '%s\n' \
    "======================================================================"

printf 'Environment      : %s\n' "${ENVIRONMENT^^}"
printf 'Control Plane    : %s\n' "${CP_TYPE}"
printf 'Terraform Dir    : %s\n' "${TERRAFORM_DIR}"
printf 'Variables File   : %s\n' "${TFVARS_FILE}"

printf '%s\n' \
    "======================================================================"
echo


################################################################################
# Fetch Konnect SAT Token
################################################################################

log_info "Fetching Konnect SAT token..."

if ! fetch_konnect_token "${ENVIRONMENT}"; then
    log_error "Failed to retrieve Konnect SAT token."
    exit 1
fi

if [[ -z "${KONNECT_TOKEN:-}" ]]; then
    log_error "Konnect SAT token is empty."
    exit 1
fi

log_success "Konnect SAT token retrieved successfully."


################################################################################
# Validate Terraform CLI
################################################################################

echo
log_info "Checking Terraform CLI..."

if ! command -v terraform >/dev/null 2>&1; then
    log_error "Terraform CLI is not installed or not available in PATH."
    exit 1
fi

TERRAFORM_VERSION="$(
    terraform version 2>/dev/null \
        | head -n 1 \
        | sed -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/' \
        || true
)"

if [[ -z "${TERRAFORM_VERSION}" ]]; then
    log_error "Unable to determine Terraform CLI version."
    terraform version
    exit 1
fi

printf '%sTerraform Version : %s%s\n' \
    "${COLOR_BLUE}" \
    "${TERRAFORM_VERSION}" \
    "${COLOR_RESET}"


################################################################################
# Terraform Initialization
#
# Normal flow:
#   terraform init
#
# Recovery flow:
#   If Terraform reports:
#
#     unsupported backend state version 4
#
#   remove ONLY the local .terraform directory and retry terraform init.
#
# IMPORTANT:
#   .terraform is local Terraform metadata/cache.
#   Removing it does NOT delete the remote GCS Terraform state.
################################################################################

initialize_terraform() {

    log_info "Initializing Terraform and connecting to remote backend..."

    if terraform -chdir="${TERRAFORM_DIR}" init \
            -input=false \
            >"${TERRAFORM_INIT_LOG}" 2>&1; then

        log_success "Terraform initialization completed."
        return 0
    fi

    # Terraform initialization failed.
    #
    # Check specifically for the backend state-version error before
    # performing recovery.
    if grep -q "unsupported backend state version" \
            "${TERRAFORM_INIT_LOG}"; then

        log_warning "Terraform local backend metadata is incompatible."
        log_info "Refreshing local Terraform initialization..."

        # Remove ONLY the local Terraform working directory.
        #
        # This does NOT remove:
        #   - Terraform configuration
        #   - terraform.tfvars
        #   - .terraform.lock.hcl
        #   - remote GCS state
        #
        # It only removes locally generated Terraform metadata/cache.
        if [[ -d "${TERRAFORM_DIR}/.terraform" ]]; then
            rm -rf "${TERRAFORM_DIR}/.terraform"
            log_info "Local .terraform directory removed."
        fi

        # Retry initialization against the configured remote backend.
        log_info "Re-initializing Terraform..."

        if terraform -chdir="${TERRAFORM_DIR}" init \
                -input=false \
                >"${TERRAFORM_INIT_LOG}" 2>&1; then

            log_success "Terraform re-initialization completed."
            return 0
        fi

        log_error "Terraform re-initialization failed."
        echo
        log_error "Terraform initialization output:"
        cat "${TERRAFORM_INIT_LOG}"
        return 1
    fi

    # Any other initialization failure should be reported normally.
    log_error "Terraform initialization failed."
    echo
    log_error "Terraform initialization output:"
    cat "${TERRAFORM_INIT_LOG}"

    return 1
}

if ! initialize_terraform; then
    exit 1
fi


################################################################################
# Verify Remote Terraform State
################################################################################

echo
log_info "Checking remote Terraform state..."

if ! terraform -chdir="${TERRAFORM_DIR}" state list \
        >"${TERRAFORM_STATE_LOG}" 2>&1; then

    log_error "Unable to read Terraform remote state."
    echo
    log_error "Terraform state output:"
    cat "${TERRAFORM_STATE_LOG}"
    exit 1
fi

if [[ ! -s "${TERRAFORM_STATE_LOG}" ]]; then
    log_warning "Terraform remote state contains no managed resources."
    log_warning "No resources are available for destruction."
    exit 0
fi

STATE_RESOURCE_COUNT="$(wc -l < "${TERRAFORM_STATE_LOG}" | tr -d ' ')"

log_success "Terraform remote state contains ${STATE_RESOURCE_COUNT} resource(s)."

echo
log_info "Resources currently managed by Terraform:"
cat "${TERRAFORM_STATE_LOG}"


################################################################################
# Terraform Destroy Plan
################################################################################

echo
log_info "Generating Terraform destroy plan..."

if ! terraform -chdir="${TERRAFORM_DIR}" plan \
        -destroy \
        -input=false \
        -var-file="${TFVARS_FILE}" \
        -out="${DESTROY_PLAN}" \
        >"${DESTROY_PLAN_LOG}" 2>&1; then

    log_error "Terraform destroy plan failed."
    echo
    log_error "Terraform failure output:"
    cat "${DESTROY_PLAN_LOG}"
    exit 1
fi


################################################################################
# Verify Destroy Plan Contains Changes
################################################################################

if grep -q "No changes" "${DESTROY_PLAN_LOG}"; then

    log_warning "Terraform reported that there are no resources to destroy."

    echo
    cat "${DESTROY_PLAN_LOG}"
    echo

    log_warning "No resources were destroyed."
    exit 0
fi

log_success "Terraform destroy plan generated."


################################################################################
# Display Destroy Plan
################################################################################

echo
printf '%s\n' \
    "======================================================================"
printf '%s\n' \
    "                    DESTROY PLAN"
printf '%s\n' \
    "======================================================================"

if ! terraform -chdir="${TERRAFORM_DIR}" show \
        "${DESTROY_PLAN}" >"${DESTROY_SHOW_LOG}" 2>&1; then

    log_error "Unable to display Terraform destroy plan."
    cat "${DESTROY_SHOW_LOG}"
    exit 1
fi

cat "${DESTROY_SHOW_LOG}"

printf '%s\n' \
    "======================================================================"
echo


################################################################################
# Confirmation
################################################################################

printf '%s\n' \
    "WARNING: The resources shown above will be permanently destroyed."

printf 'Environment   : %s\n' "${ENVIRONMENT^^}"
printf 'Control Plane : %s\n' "${CP_TYPE}"
echo

read -r -p "Type 'yes' to continue with destruction: " CONFIRMATION

if [[ "${CONFIRMATION}" != "yes" ]]; then
    log_info "Destruction cancelled."
    exit 0
fi


################################################################################
# Terraform Destroy
################################################################################

echo
log_info "Destroying Terraform-managed Konnect resources..."

if ! terraform -chdir="${TERRAFORM_DIR}" apply \
        -input=false \
        "${DESTROY_PLAN}" \
        >"${DESTROY_LOG}" 2>&1; then

    log_error "Terraform destroy failed."
    echo
    log_error "Terraform failure output:"
    cat "${DESTROY_LOG}"
    exit 1
fi

log_success "Konnect resources destroyed successfully."


################################################################################
# Completion
################################################################################

echo
printf '%s\n' \
    "======================================================================"
printf '%s\n' \
    "                    DESTRUCTION COMPLETE"
printf '%s\n' \
    "======================================================================"

printf 'Environment      : %s\n' "${ENVIRONMENT^^}"
printf 'Control Plane    : %s\n' "${CP_TYPE}"

printf '%s\n' \
    "======================================================================"
