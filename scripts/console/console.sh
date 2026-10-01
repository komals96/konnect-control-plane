#!/usr/bin/env bash
# Interactive input collection for run_pipeline.sh.

CONSOLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=summary.sh
source "${CONSOLE_DIR}/summary.sh"

choose_command() {
    local choice

    while true; do
        printf 'Choose an action:\n'
        printf '  1) CI (plan)\n'
        printf '  2) CD (apply)\n'
        printf '  3) Export outputs\n'
        printf '  4) Full pipeline (CI, CD, export)\n'
        read -r -p 'Selection [1-4]: ' choice

        case "${choice}" in
            1) COMMAND='ci'; return ;;
            2) COMMAND='cd'; return ;;
            3) COMMAND='export'; return ;;
            4) COMMAND='all'; return ;;
            *) error 'Please enter a number from 1 to 4.' ;;
        esac
    done
}

choose_environment() {
    read -r -p 'Environment (for example: dev, uat, ppd, prd): ' ENVIRONMENT
    ENVIRONMENT="${ENVIRONMENT,,}"

    if [[ -z "${ENVIRONMENT}" ]]; then
        error 'Environment is required.'
        return 1
    fi
}

choose_cp_type() {
    local choice

    while true; do
        printf 'Choose a control-plane type:\n'
        printf '  1) ONPREM\n'
        printf '  2) GCLOUD\n'
        read -r -p 'Selection [1-2]: ' choice

        case "${choice}" in
            1) CP_TYPE='ONPREM'; return ;;
            2) CP_TYPE='GCLOUD'; return ;;
            *) error 'Please enter 1 or 2.' ;;
        esac
    done
}

collect_pipeline_inputs() {
    print_banner
    choose_command
    choose_environment
    choose_cp_type
    print_selection_summary "${COMMAND}" "${ENVIRONMENT}" "${CP_TYPE}"
}
