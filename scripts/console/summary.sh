#!/usr/bin/env bash
# Presentation helpers for the interactive pipeline console.

CONSOLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=colors.sh
source "${CONSOLE_DIR}/colors.sh"

PIPELINE_START_EPOCH=''
PIPELINE_STEP_RESULTS=()

print_rule() {
    printf '%s\n' '======================================================================'
}

print_banner() {
    printf '\n'
    print_rule
    printf '%s                  KONNECT CONTROL PLANE AUTOMATION%s\n' \
        "${COLOR_BOLD}${COLOR_BLUE}" "${COLOR_RESET}"
    print_rule
}

start_pipeline_console() {
    local environment="$1" cp_type="$2" project_id="$3" workspace="$4" repository="$5"

    PIPELINE_START_EPOCH="$(date +%s)"
    PIPELINE_STEP_RESULTS=()
    print_banner
    printf 'Environment      : %s\n' "${environment^^}"
    printf 'Control Plane    : %s\n' "${cp_type}"
    printf 'GCP Project      : %s\n' "${project_id}"
    printf 'Workspace        : %s\n' "${workspace}"
    printf 'Repository       : %s\n' "${repository}"
    printf 'Execution Time   : %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
}

start_step() {
    local number="$1" total="$2" title="$3"
    print_rule
    printf '%sSTEP %s/%s  %s%s\n' "${COLOR_BOLD}" "${number}" "${total}" "${title}" "${COLOR_RESET}"
    print_rule
    printf '\n'
}

pass() {
    printf '%s✔%s %s\n' "${COLOR_GREEN}" "${COLOR_RESET}" "$*"
}

warning() {
    printf '%s⚠️%s %s\n' "${COLOR_YELLOW}" "${COLOR_RESET}" "$*"
}

fail() {
    printf '%s✘%s %s\n' "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2
}

record_step_result() {
    PIPELINE_STEP_RESULTS+=("$1|$2")
}

run_stage() {
    local number="$1" total="$2" title="$3"
    shift 3

    start_step "${number}" "${total}" "${title}"

    "$@"
    local result=$?

    if [[ "${result}" -eq 0 ]]; then
        printf '\nVerification\n\n'
        pass "${title} completed successfully"
        printf '\nStatus : %sPASS%s\n\n' \
            "${COLOR_GREEN}" \
            "${COLOR_RESET}"

        record_step_result "${title}" 'PASS'
        return 0

    elif [[ "${result}" -eq 2 ]]; then
        printf '\nVerification\n\n'
        warning "${title} completed with warnings"
        printf '\nStatus : %sWARNING%s\n\n' \
            "${COLOR_YELLOW}" \
            "${COLOR_RESET}"

        record_step_result "${title}" 'WARNING'
        return 0

    else
        printf '\nVerification\n\n' >&2
        fail "${title} failed. Review the error above."

        printf '\nStatus : %sFAIL%s\n\n' \
            "${COLOR_RED}" \
            "${COLOR_RESET}" >&2

        record_step_result "${title}" 'FAIL'
        return 1
    fi
}

format_duration() {
    local seconds="$1"
    printf '%02dm %02ds' "$((seconds / 60))" "$((seconds % 60))"
}

print_final_summary() {
    local elapsed status=SUCCESS item title result
    elapsed="$(( $(date +%s) - PIPELINE_START_EPOCH ))"

    print_rule
    printf '%sFINAL EXECUTION SUMMARY%s\n' "${COLOR_BOLD}${COLOR_BLUE}" "${COLOR_RESET}"
    print_rule
    printf '\n'

    for item in "${PIPELINE_STEP_RESULTS[@]}"; do
        title="${item%%|*}"
        result="${item##*|}"
        printf '%-30s %s%s%s\n' "${title}" \
            "$([[ "${result}" == PASS ]] && printf '%s' "${COLOR_GREEN}" || printf '%s' "${COLOR_RED}")" \
            "${result}" "${COLOR_RESET}"
        [[ "${result}" == PASS ]] || status=FAILURE
    done

    printf '\nOverall Status                %s%s%s\n' \
        "$([[ "${status}" == SUCCESS ]] && printf '%s' "${COLOR_GREEN}" || printf '%s' "${COLOR_RED}")" \
        "${status}" "${COLOR_RESET}"
    printf 'Execution Time                %s\n\n' "$(format_duration "${elapsed}")"
    print_rule

    [[ "${status}" == SUCCESS ]]
}

print_selection_summary() {
    printf '%sCommand:%s     %s\n' "${COLOR_BOLD}" "${COLOR_RESET}" "$1"
    printf '%sEnvironment:%s %s\n' "${COLOR_BOLD}" "${COLOR_RESET}" "$2"
    printf '%sCP type:%s     %s\n\n' "${COLOR_BOLD}" "${COLOR_RESET}" "$3"
}

info() {
    printf '%s[INFO]%s %s\n' "${COLOR_BLUE}" "${COLOR_RESET}" "$*"
}

success() {
    printf '%s[SUCCESS]%s %s\n' "${COLOR_GREEN}" "${COLOR_RESET}" "$*"
}

error() {
    printf '%s[ERROR]%s %s\n' "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2
}


