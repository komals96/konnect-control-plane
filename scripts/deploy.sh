#!/usr/bin/env bash

# Run the Terraform CI/CD/export/token-rotation scripts
# for a selected environment and Control Plane type.
set -euo pipefail


################################################################################
# Script Paths
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}"


################################################################################
# Source Common Scripts
################################################################################

# shellcheck source=console/summary.sh
source "${SCRIPT_DIR}/console/summary.sh"

# shellcheck source=common/fetch_konnect_token.sh
source "${SCRIPT_DIR}/common/fetch_konnect_token.sh"

# shellcheck source=konnect_environment_resolver.sh
source "${SCRIPT_DIR}/konnect_environment_resolver.sh"


################################################################################
# Usage
################################################################################

usage() {
    cat <<'EOF'

Usage:
  ./scripts/deploy.sh <environment> <onprem|gcloud>
  ./scripts/deploy.sh ci     <environment> <onprem|gcloud>
  ./scripts/deploy.sh cd     <environment> <onprem|gcloud>
  ./scripts/deploy.sh export <environment> <onprem|gcloud>
  ./scripts/deploy.sh all    <environment> <onprem|gcloud>

Commands:
  <environment> <CP type>
      Run the complete Control Plane setup pipeline.
      This includes:
        - Prerequisite validation
        - SAT token retrieval
        - Terraform CI
        - Terraform CD
        - Konnect resource verification
        - Metadata export
        - Platform Ops token rotation check
        - API Ops token rotation check

  ci
      Run Terraform init, validate, and plan.

  cd
      Apply the saved Terraform plan and generate the CP configuration.

  export
      Export existing Terraform outputs and metadata only.

  all
      Run the complete Control Plane setup pipeline.

Examples:

  ./scripts/deploy.sh dev gcloud
  ./scripts/deploy.sh dev onprem

  ./scripts/deploy.sh ci dev gcloud
  ./scripts/deploy.sh cd dev gcloud
  ./scripts/deploy.sh export dev gcloud
  ./scripts/deploy.sh all dev gcloud

EOF
}


################################################################################
# Parse Arguments
################################################################################

if [[ $# -eq 0 ]]; then

    # shellcheck source=console/console.sh
    source "${SCRIPT_DIR}/console/console.sh"

    collect_pipeline_inputs

elif [[ $# -eq 3 ]]; then

    COMMAND="$1"
    ENVIRONMENT="$2"
    CP_TYPE="${3^^}"

elif [[ $# -eq 2 ]]; then

    COMMAND="all"
    ENVIRONMENT="$1"
    CP_TYPE="${2^^}"

else

    usage >&2
    exit 1

fi


################################################################################
# Validate Control Plane Type
################################################################################

case "${CP_TYPE}" in

    ONPREM)

        SCOPE="onprem-cp"
        BITBUCKET_REPOSITORY="kong-onprem-dp-itg"
        ;;

    GCLOUD)

        SCOPE="gcloud-cp"
        BITBUCKET_REPOSITORY="N/A"
        ;;

    *)

        error "CP type must be ONPREM or GCLOUD."
        exit 1
        ;;

esac


################################################################################
# Terraform Configuration
################################################################################

TERRAFORM_DIR="${REPO_ROOT}/env/${ENVIRONMENT}/${SCOPE}"


################################################################################
# Resolve Environment Configuration
################################################################################

resolve_konnect_environment "${ENVIRONMENT}" || exit 1

GCP_PROJECT_ID="${KONNECT_PROJECT_ID}"
export GCP_PROJECT_ID

BITBUCKET_WORKSPACE="${BITBUCKET_WORKSPACE:-oreillyauto}"

################################################################################
# Validate Command
################################################################################

case "${COMMAND}" in

    ci|cd|export|all)
        ;;

    *)
        error "Unknown command: ${COMMAND}"
        usage >&2
        exit 1
        ;;

esac


################################################################################
# Pipeline Functions
################################################################################

################################################################################
# Step: Validate Prerequisites
################################################################################

run_prerequisites() {

    info "Validating prerequisites for ${ENVIRONMENT}/${CP_TYPE}."

    bash "${SCRIPTS_DIR}/common/validate_prerequisites.sh" \
        "${ENVIRONMENT}" \
        "${CP_TYPE}"
}


################################################################################
# Step: Fetch SAT Token
################################################################################

run_fetch_token() {

    # Konnect SAT authentication is global and ALWAYS comes from PROD.
    # Do not use the target environment project for SAT retrieval.
    info "Retrieving Konnect SAT token from PROD Secret Manager."
    info "SAT Project: ${KONNECT_PROJECT_ID_SAT}"
    info "SAT Secret : ${SAT_SECRET_NAME}"

    fetch_konnect_token

    export KONNECT_TOKEN
}


################################################################################
# Step: Terraform CI
################################################################################

run_ci() {

    info "Running CI for ${ENVIRONMENT}/${CP_TYPE}."

    (
        cd "${TERRAFORM_DIR}"

        bash "${SCRIPTS_DIR}/ci_runner.sh"
    )
}


################################################################################
# Step: Validate ONPREM Bitbucket Credentials
################################################################################

validate_onprem_bitbucket_credentials() {

    if [[ -z "${BITBUCKET_USERNAME:-}" ||
          -z "${BITBUCKET_TOKEN:-}" ]]; then

        error 'ONPREM export requires BITBUCKET_USERNAME and BITBUCKET_TOKEN.'
        error 'Set both environment variables before running the pipeline.'

        return 1
    fi

    pass 'Bitbucket credentials are available'
}


################################################################################
# Step: Terraform CD
################################################################################

run_cd() {

    info "Running CD for ${ENVIRONMENT}/${CP_TYPE}."

    (
        cd "${TERRAFORM_DIR}"

        ENVIRONMENT="${ENVIRONMENT}" \
        CP_TYPE="${CP_TYPE}" \
            bash "${SCRIPTS_DIR}/cd_runner.sh"
    )
}


################################################################################
# Step: Verify Konnect Resources
################################################################################

run_verify() {

    info \
        "Verifying Terraform-created Konnect resources for ${ENVIRONMENT}/${CP_TYPE}."

    (
        cd "${TERRAFORM_DIR}"

        bash "${SCRIPTS_DIR}/common/verify_konnect_resources.sh" \
        "${CP_TYPE}"
    )
}


################################################################################
# Step: Export CP Metadata
################################################################################

run_export() {

    info "Exporting outputs for ${ENVIRONMENT}/${CP_TYPE}."

    bash "${SCRIPTS_DIR}/export_tf_outputs.sh" \
        "${ENVIRONMENT}" \
        "${CP_TYPE}" \
        "${GCP_PROJECT_ID}"
}



################################################################################
# Step: Token Rotation
################################################################################
#
# Token rotation is part of the Control Plane setup flow.
#
# Rotation order:
#
#   1. Platform Ops
#      - Global Platform Ops token
#      - Environment is used to resolve the appropriate Secret Manager
#        project/secret.
#      - No Control Plane type is required.
#
#   2. API Ops
#      - CP-specific API Ops token
#      - Requires environment and Control Plane type.
#
# The token_rotation.sh script itself determines whether rotation is
# actually required based on token expiry/rotation threshold.
#
# Therefore, running deploy.sh does NOT necessarily create a new token.
#
################################################################################

 run_token_rotation() {

     info "Checking Konnect token rotation for ${ENVIRONMENT}/${CP_TYPE}."


#     ############################################################################
#     # Platform Ops Token
#     ############################################################################
#     #
#     # Platform Ops is environment-specific in Secret Manager but is not
#     # Control Plane-specific.
#     #
#     # Usage:
#     #
#     #   token_rotation.sh <environment> PLATFORM_OPS
#     #
#     ############################################################################

#     info "Checking Platform Ops token rotation."

#     bash "${SCRIPTS_DIR}/operations/token_rotation.sh" \
#         "${ENVIRONMENT}" \
#         PLATFORM_OPS


    ############################################################################
    # API Ops Token
    ############################################################################
    #
    # API Ops is Control Plane-specific.
    #
    # Usage:
    #
    #   token_rotation.sh <environment> API_OPS <ttl-days> <CP_TYPE>
    #
    ############################################################################

    info "Checking API Ops token rotation."

    bash "${SCRIPTS_DIR}/operations/token_rotation.sh" \
        "${ENVIRONMENT}" \
        api-ops \
        "${TOKEN_TTL_DAYS:-365}" \
        "${CP_TYPE,,}"


    ############################################################################
    # Rotation Complete
    ############################################################################

    pass "Konnect token rotation checks completed successfully."
}


################################################################################
# Start Pipeline Console
################################################################################

start_pipeline_console \
    "${ENVIRONMENT}" \
    "${CP_TYPE}" \
    "${GCP_PROJECT_ID}" \
    "${BITBUCKET_WORKSPACE}" \
    "${BITBUCKET_REPOSITORY}"


################################################################################
# Execute Pipeline
################################################################################

case "${COMMAND}" in


    ############################################################################
    # CI
    ############################################################################

    ci)

        run_stage 1 3 \
            'Validate prerequisites' \
            run_prerequisites \
            || {
                print_final_summary
                exit 1
            }

        run_stage 2 3 \
            'Fetch SAT token' \
            run_fetch_token \
            || {
                print_final_summary
                exit 1
            }

        run_stage 3 3 \
            'Terraform CI (init, validate, plan)' \
            run_ci \
            || {
                print_final_summary
                exit 1
            }

        ;;


    ############################################################################
    # CD
    ############################################################################

    cd)

        run_stage 1 4 \
            'Validate prerequisites' \
            run_prerequisites \
            || {
                print_final_summary
                exit 1
            }

        run_stage 2 4 \
            'Fetch SAT token' \
            run_fetch_token \
            || {
                print_final_summary
                exit 1
            }

        run_stage 3 4 \
            'Terraform CD (apply and metadata generation)' \
            run_cd \
            || {
                print_final_summary
                exit 1
            }

        # run_stage 4 4 \
        #     'Verify Konnect resources' \
        #     run_verify \
        #     || {
        #         print_final_summary
        #         exit 1
        #     }

        ;;


    ############################################################################
    # EXPORT
    ############################################################################

    export)

        if [[ "${CP_TYPE}" == "ONPREM" ]]; then

            run_stage 1 3 \
                'Validate prerequisites' \
                run_prerequisites \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 2 3 \
                'Validate Bitbucket credentials' \
                validate_onprem_bitbucket_credentials \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 3 3 \
                'Export metadata and repository update' \
                run_export \
                || {
                    print_final_summary
                    exit 1
                }

        else

            run_stage 1 2 \
                'Validate prerequisites' \
                run_prerequisites \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 2 2 \
                'Export metadata' \
                run_export \
                || {
                    print_final_summary
                    exit 1
                }

        fi

        ;;


    ############################################################################
    # FULL CONTROL PLANE SETUP
    ############################################################################

    all)

        ############################################################################
        # ONPREM
        ############################################################################

        if [[ "${CP_TYPE}" == "ONPREM" ]]; then

            run_stage 1 8 \
                'Validate prerequisites' \
                run_prerequisites \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 2 8 \
                'Fetch SAT token' \
                run_fetch_token \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 3 8 \
                'Validate Bitbucket credentials' \
                validate_onprem_bitbucket_credentials \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 4 8 \
                'Terraform CI (init, validate, plan)' \
                run_ci \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 5 8 \
                'Terraform CD (apply and metadata generation)' \
                run_cd \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 6 8 \
                'Verify Konnect resources' \
                run_verify \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 7 8 \
                'Export metadata and create pull request' \
                run_export \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 8 8 \
                'Check and rotate Konnect tokens' \
                run_token_rotation \
                || {
                    print_final_summary
                    exit 1
                }

        ############################################################################
        # GCLOUD
        ############################################################################

        else

            run_stage 1 7 \
                'Validate prerequisites' \
                run_prerequisites \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 2 7 \
                'Fetch SAT token' \
                run_fetch_token \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 3 7 \
                'Terraform CI (init, validate, plan)' \
                run_ci \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 4 7 \
                'Terraform CD (apply and metadata generation)' \
                run_cd \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 5 7 \
                'Verify Konnect resources' \
                run_verify \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 6 7 \
                'Export metadata' \
                run_export \
                || {
                    print_final_summary
                    exit 1
                }

            run_stage 7 7 \
                'Check and rotate Konnect tokens' \
                run_token_rotation \
                || {
                    print_final_summary
                    exit 1
                }

        fi

        ;;

esac


################################################################################
# Final Summary
################################################################################

print_final_summary