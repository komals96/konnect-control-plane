#!/bin/bash
set -e
################################################################################
# Script Name : apply_konnect_sat_plan.sh
#
# Purpose:
#   This script applies Terraform plan using Konnect SAT token retrieved from
#   GCP Secret Manager and generates CP configuration metadata.
#
# Flow:
#   1. Authenticate with GCP Service Account
#   2. Retrieve Konnect SAT token from Secret Manager
#   3. Apply Terraform plan
#   4. Export Terraform CP configuration output
#   5. Trigger export_tf_outputs.sh to update Secret Manager / repository
#
# Usage:
#   ./script.sh
#
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=console/colors.sh
source "${SCRIPT_DIR}/console/colors.sh"


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
# Directory Configuration
#
# SCRIPT_DIR:
#   Directory where current script exists
#
# PROJECT_DIR:
#   Terraform working directory
#
# REPO_ROOT:
#   Root directory containing export_tf_outputs.sh
#
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"


################################################################################
# Function : apply_terraform_plan
#
# Purpose:
#   Applies previously generated Terraform plan file.
#
# Input:
#   tfplan file generated during terraform plan execution
#
################################################################################

apply_terraform_plan() {


    log_info  "Applying Terraform plan..."


    if [[ ! -f "tfplan" ]]; then

        log_error "Terraform plan file 'tfplan' not found."

        return 1

    fi



    terraform apply tfplan



    log_success "Terraform apply completed."

}



################################################################################
# Function : generate_cp_config
#
# Purpose:
#   Exports Terraform output cp_config_yaml
#   into cp-config.yml file.
#
# Output:
#   ${PROJECT_DIR}/cp-config.yml
#
################################################################################

# generate_cp_config() {


#     log_info "Generating cp-config.yml from Terraform output..."



#     terraform output -raw cp_config_yaml \
#         > "${PROJECT_DIR}/cp-config.yml"



#     log_success "Terraform output written:"
#     log_info "${PROJECT_DIR}/cp-config.yml"


# }



################################################################################
# Function : collect_runtime_inputs
#
# Purpose:
#   Collects environment and CP type values.
#
# Inputs:
#   ENVIRONMENT -> dev/uat/ppd/prd
#   CP_TYPE     -> ONPREM/GCLOUD
#
################################################################################

collect_runtime_inputs() {


    if [[ -z "${ENVIRONMENT:-}" ]]; then

        read -p "Enter environment (e.g. dev): " ENVIRONMENT

    fi



    if [[ -z "${CP_TYPE:-}" ]]; then

        read -p "Enter CP_TYPE (ONPREM or GCLOUD): " CP_TYPE

    fi



    if [[ -z "${ENVIRONMENT}" || -z "${CP_TYPE}" ]]; then

        echo "Environment and CP_TYPE are mandatory."

        exit 1

    fi



    log_info "Environment : ${ENVIRONMENT}"
    log_info "CP Type     : ${CP_TYPE}"


}

################################################################################
# Main execution flow
################################################################################

main() {

    printf '\n%s================================================%s\n' \
        "${COLOR_BLUE}${COLOR_BOLD}" \
        "${COLOR_RESET}"

    printf '%s Starting Konnect Terraform Apply Automation%s\n' \
        "${COLOR_BLUE}${COLOR_BOLD}" \
        "${COLOR_RESET}"

    printf '%s================================================%s\n' \
        "${COLOR_BLUE}${COLOR_BOLD}" \
        "${COLOR_RESET}"


     apply_terraform_plan


    #generate_cp_config


    collect_runtime_inputs


    printf '%s===========================================================%s\n' \
        "${COLOR_GREEN}${COLOR_BOLD}" \
        "${COLOR_RESET}"

    printf '%s Terraform apply automation completed successfully%s\n' \
        "${COLOR_GREEN}${COLOR_BOLD}" \
        "${COLOR_RESET}"

    printf '%s===========================================================%s\n' \
        "${COLOR_GREEN}${COLOR_BOLD}" \
        "${COLOR_RESET}"

}

main