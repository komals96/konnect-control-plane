#!/usr/bin/env bash

################################################################################
# Shared Konnect environment helpers
#
# This file is sourced by other scripts.
# It must NOT:
#   - enable shell options
#   - execute a main function
#   - perform any environment-specific actions automatically
################################################################################

resolve_konnect_environment() {

    local environment="${1,,}"

    case "${environment}" in

        dev|uat)
            KONNECT_PROJECT_ID="us-nprd-itg-api-kong-01"
            ;;

        ppd)
            KONNECT_PROJECT_ID="us-pprd-itg-api-kong-01"
            ;;

        prd)
            KONNECT_PROJECT_ID="us-prod-itg-api-kong-01"
            ;;

        *)
            printf '[ERROR] Unsupported environment: %s\n' \
                "${environment}" >&2
            return 1
            ;;
    esac

    export KONNECT_PROJECT_ID

    return 0
}
