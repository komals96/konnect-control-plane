#!/bin/bash
set -e

################################################################################
# Script Name : terraform_plan_with_konnect_token.sh
#
# Purpose:
#   This script performs Terraform validation and plan generation using
#   Konnect SAT token fetched securely from GCP Secret Manager.
#
# Terraform logging behavior:
#   - Suppress normal Terraform init output
#   - Suppress normal Terraform validate output
#   - Suppress Terraform plan/resource details from CI console
#   - Display Terraform output only when a command fails
#   - Keep tfplan available for later application
#
# Flow:
#   1. Authenticate to GCP using Service Account
#   2. Fetch Konnect SAT token from Secret Manager
#   3. Extract token value from JSON secret payload
#   4. Validate token availability
#   5. Initialize Terraform
#   6. Validate Terraform configuration
#   7. Generate Terraform plan using SAT token
#
################################################################################


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=console/colors.sh
source "${SCRIPT_DIR}/console/colors.sh"

# shellcheck source=common/fetch_konnect_token.sh
source "${SCRIPT_DIR}/common/fetch_konnect_token.sh"


################################################################################
# Logging Functions
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
# Temporary Terraform Log Directory
#
# Terraform command output is captured here instead of being printed directly
# to the CI console.
################################################################################

TERRAFORM_LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/terraform-ci.XXXXXX")"

TERRAFORM_INIT_LOG="${TERRAFORM_LOG_DIR}/terraform-init.log"
TERRAFORM_VALIDATE_LOG="${TERRAFORM_LOG_DIR}/terraform-validate.log"
TERRAFORM_PLAN_LOG="${TERRAFORM_LOG_DIR}/terraform-plan.log"

################################################################################
# Cleanup
################################################################################
cleanup_terraform_logs() {
    rm -rf "${TERRAFORM_LOG_DIR}"
}

trap cleanup_terraform_logs EXIT


################################################################################
# Function : terraform_execution
#
# Purpose:
#   Initializes Terraform, validates configuration,
#   and generates Terraform execution plan using
#   Konnect SAT token.
#
# Logging:
#   Terraform stdout/stderr is captured into temporary log files.
#   Successful Terraform output is NOT displayed.
#   Terraform output is displayed only when a command fails.
#
################################################################################

terraform_execution() {
    
    log_terraform_state() {

    local backend_config=".terraform/terraform.tfstate"
    local bucket
    local prefix

    if [[ ! -f "${backend_config}" ]]; then
        log_error "Terraform backend configuration file not found."
        return 1
    fi

    bucket="$(sed -nE \
        's/.*"bucket"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
        "${backend_config}" | head -n 1)"

    prefix="$(sed -nE \
        's/.*"prefix"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' \
        "${backend_config}" | head -n 1)"

    if [[ -z "${bucket}" ]]; then
        log_error "Unable to determine Terraform state bucket."
        return 1
    fi

    if [[ -z "${prefix}" ]]; then
        log_error "Unable to determine Terraform state prefix."
        return 1
    fi

    log_info "Terraform State"
    printf '      %sBucket%s : %s%s%s\n' \
        "${COLOR_BOLD}" \
        "${COLOR_RESET}" \
        "${COLOR_CYAN}" \
        "${bucket}" \
        "${COLOR_RESET}"

    printf '      %sPrefix%s : %s%s%s\n' \
        "${COLOR_BOLD}" \
        "${COLOR_RESET}" \
        "${COLOR_CYAN}" \
        "${prefix}" \
        "${COLOR_RESET}"
    }

    ########################################################################
    # Terraform Init
    ########################################################################

    log_info 'Initializing Terraform...'
    if terraform init \
        -reconfigure \
        -no-color \
        >"${TERRAFORM_INIT_LOG}" 2>&1; then

        log_success 'Terraform initialization completed.'

        log_terraform_state

    else
        log_error 'Terraform initialization failed.'
        log_error 'Terraform output:'
        cat "${TERRAFORM_INIT_LOG}"
        return 1
    fi

    ########################################################################
    # Terraform Validate
    #
    # Normal/successful output is suppressed.
    # Complete Terraform output is displayed when validation fails.
    ########################################################################

    log_info 'Validating Terraform configuration...'

    if terraform validate \
        -no-color \
        >"${TERRAFORM_VALIDATE_LOG}" 2>&1; then

        log_success 'Terraform validation completed.'

    else
        VALIDATE_EXIT_CODE=$?

        log_error 'Terraform validation failed.'
        printf '\n'

        printf '%s======================================================================%s\n' \
            "${COLOR_RED}${COLOR_BOLD}" \
            "${COLOR_RESET}"

        printf '%s              TERRAFORM VALIDATION ERROR%s\n' \
            "${COLOR_RED}${COLOR_BOLD}" \
            "${COLOR_RESET}"

        printf '%s======================================================================%s\n' \
            "${COLOR_RED}${COLOR_BOLD}" \
            "${COLOR_RESET}"

        printf '\n'

        # Always display the complete Terraform validation output.
        if [[ -s "${TERRAFORM_VALIDATE_LOG}" ]]; then
            cat "${TERRAFORM_VALIDATE_LOG}"
        else
            log_error 'Terraform validation produced no output.'
        fi

        printf '\n'
        printf '%s======================================================================%s\n' \
            "${COLOR_RED}${COLOR_BOLD}" \
            "${COLOR_RESET}"

        printf '\n'

        return "${VALIDATE_EXIT_CODE}"
    fi


    ########################################################################
    # Terraform Plan
    #
    # The complete Terraform plan output is captured in a temporary log.
    #
    # This prevents the following from appearing in the CI console:
    #
    #   module.xxx: Refreshing state...
    #   Objects have changed outside of Terraform
    #   resource "..."
    #   + create
    #   - destroy
    #   Plan: X to add, X to change, X to destroy
    #   Changes to Outputs
    #
    # The actual plan is still saved to tfplan.
    ########################################################################

    if terraform plan \
        -no-color \
        -out=tfplan \
        -var="${KONNECT_TOKEN}" \
        >"${TERRAFORM_PLAN_LOG}" 2>&1; 
        then

        log_success 'Terraform plan generated successfully.'

    else
        log_error 'Terraform plan failed.'
        log_error 'Terraform output:'
        cat "${TERRAFORM_PLAN_LOG}"
        return 1
    fi

}


################################################################################
# Main execution flow
################################################################################

main() {

    printf '\n%s================================================%s\n' \
        "${COLOR_BLUE}${COLOR_BOLD}" \
        "${COLOR_RESET}"

    printf '%s Starting Terraform Plan Automation%s\n' \
        "${COLOR_BLUE}${COLOR_BOLD}" \
        "${COLOR_RESET}"

    printf '%s================================================%s\n' \
        "${COLOR_BLUE}${COLOR_BOLD}" \
        "${COLOR_RESET}"


    terraform_execution


    printf '%s================================================%s\n' \
        "${COLOR_GREEN}${COLOR_BOLD}" \
        "${COLOR_RESET}"

    printf '%s tfplan automation completed successfully%s\n' \
        "${COLOR_GREEN}${COLOR_BOLD}" \
        "${COLOR_RESET}"

    printf '%s================================================%s\n' \
        "${COLOR_GREEN}${COLOR_BOLD}" \
        "${COLOR_RESET}"

}


main