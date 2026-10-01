#!/usr/bin/env bash
# Verify resources created by Terraform against the Konnect APIs.
# IDs are read from `terraform output -json verification_targets`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../console/colors.sh
source "${SCRIPT_DIR}/../console/colors.sh"

KONNECT_REGION="${KONNECT_REGION:-us}"
KONNECT_API_BASE="${KONNECT_API_BASE:-https://${KONNECT_REGION}.api.konghq.com}"
KONNECT_GLOBAL_API_BASE="${KONNECT_GLOBAL_API_BASE:-https://global.api.konghq.com}"
MAX_ATTEMPTS="${KONNECT_VERIFY_ATTEMPTS:-5}"
RETRY_SECONDS="${KONNECT_VERIFY_RETRY_SECONDS:-3}"

###############################################################################
# Control Plane Type
###############################################################################

# Accept CP_TYPE from the first argument.
# Fall back to the environment variable if no argument is provided.
CP_TYPE="${1:-${CP_TYPE:-}}"

# Normalize to lowercase so input is case-insensitive.
CP_TYPE="${CP_TYPE,,}"

if [[ "${CP_TYPE}" != "onprem" && "${CP_TYPE}" != "gcloud" ]]; then
    printf '%s\n' \
        '[ERROR] CP_TYPE must be set to either "onprem" or "gcloud" before running verification.' >&2
    exit 1
fi

for command in terraform curl jq; do
    command -v "${command}" >/dev/null 2>&1 || {
        printf '[ERROR] %s is required for Konnect verification.\n' "${command}" >&2
        exit 1
    }
done

if [[ -z "${KONNECT_TOKEN:-}" ]]; then
    printf '%s\n' '[ERROR] KONNECT_TOKEN must be set before running verification.' >&2
    exit 1
fi

targets="$(terraform output -json verification_targets)" || {
    printf '%s\n' '[ERROR] Terraform output verification_targets is unavailable.' >&2
    exit 1
}

passed=0
failed=0

verify_get() {
    local name="$1" url="$2" expected_id="${3:-}" attempt code body

    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        body="$(mktemp)"
        code="$(curl --silent --show-error --location --output "${body}" --write-out '%{http_code}' \
            --header "Authorization: Bearer ${KONNECT_TOKEN}" \
            --header 'Accept: application/json' "${url}" || true)"

        if [[ "${code}" =~ ^2[0-9][0-9]$ ]] && \
           { [[ -z "${expected_id}" ]] || jq -e --arg id "${expected_id}" '.id == $id' "${body}" >/dev/null 2>&1; }; then
            printf '%s[PASS]%s %s (HTTP %s)\n' \
                "${COLOR_GREEN}" "${COLOR_RESET}" "${name}" "${code}"
            rm -f "${body}"
            ((passed += 1))
            return 0
        fi

        rm -f "${body}"
        if (( attempt < MAX_ATTEMPTS )); then
            sleep "${RETRY_SECONDS}"
        fi
    done

    printf '%s[FAIL]%s %s (last HTTP %s)\n' \
        "${COLOR_RED}" "${COLOR_RESET}" "${name}" "${code:-000}" >&2
    ((failed += 1))
    return 0
}

verify_global_plugins() {
    local url="$1"
    local expected_plugins="$2"
    local cp_type="$3"
    local attempt code body
    local plugins_response
    local otel_plugin
    local otel_access_logs_endpoint
    local otel_logs_endpoint
    local otel_metrics_endpoint
    local otel_traces_endpoint
    local rl_plugin
    local rl_strategy
    local redis_values
    local value
    local redis_index
    local field
    local sentinel_nodes
    local sentinel_master
    local sentinel_role

    for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
        body="$(mktemp)"
        code="$(curl --silent --show-error --location --output "${body}" --write-out '%{http_code}' \
            --header "Authorization: Bearer ${KONNECT_TOKEN}" \
            --header 'Accept: application/json' "${url}" || true)"

        if [[ "${code}" =~ ^2[0-9][0-9]$ ]] && \
           jq -e --argjson expected "${expected_plugins}" '
               [.data[]?
                | select((.service? // null) == null)
                | select((.route? // null) == null)
                | select((.consumer? // null) == null)
                | select((.consumer_group? // null) == null)
                | .name] as $global_plugin_names
               | all($expected[]; . as $expected_name | $global_plugin_names | index($expected_name) != null)
           ' "${body}" >/dev/null 2>&1; then

            printf '%s[PASS]%s Global plugins (HTTP %s)\n' \
                "${COLOR_GREEN}" "${COLOR_RESET}" "${code}"
            ((passed += 1))

            plugins_response="$(cat "${body}")"
            rm -f "${body}"

            # ----------------------------------------------------------------
            # OpenTelemetry global plugin configuration checks
            # ----------------------------------------------------------------
            printf '\n-- Global Plugin Configuration Checks --\n'

            otel_plugin="$(echo "${plugins_response}" | jq -c '
                .data[]?
                | select(.name == "opentelemetry")
                | select(
                    (.route == null) and
                    (.service == null) and
                    (.consumer == null) and
                    (.consumer_group == null)
                  )
            ' | head -n 1)"

            if [[ -z "${otel_plugin}" ]]; then
                printf '%s[FAIL]%s Global OpenTelemetry plugin not found\n' \
                    "${COLOR_RED}" "${COLOR_RESET}"
                ((failed += 1))
            else
                printf '%s[PASS]%s Global OpenTelemetry plugin found\n' \
                    "${COLOR_GREEN}" "${COLOR_RESET}"
                ((passed += 1))

                # ------------------------------------------------------------
                # Access logs endpoint
                # ------------------------------------------------------------
                otel_access_logs_endpoint="$(echo "${otel_plugin}" | jq -r \
                    '.config.access_logs.endpoint // empty')"

                # ------------------------------------------------------------
                # Logs endpoint
                # ------------------------------------------------------------
                otel_logs_endpoint="$(echo "${otel_plugin}" | jq -r \
                    '.config.logs_endpoint // empty')"

                # ------------------------------------------------------------
                # Metrics endpoint
                # ------------------------------------------------------------
                otel_metrics_endpoint="$(echo "${otel_plugin}" | jq -r \
                    '.config.metrics.endpoint // empty')"

                # ------------------------------------------------------------
                # Traces endpoint
                # ------------------------------------------------------------
                otel_traces_endpoint="$(echo "${otel_plugin}" | jq -r \
                    '.config.traces_endpoint // empty')"

                # ----------------------------------------------------------------
                # Validate Vault references
                # ----------------------------------------------------------------

                # Access logs endpoint:
                # Vault reference is required only for on-prem.
                if [[ "${cp_type}" == "onprem" ]]; then
                    if [[ "${otel_access_logs_endpoint}" == *"{vault://"* ]]; then
                        printf '%s[PASS]%s OpenTelemetry access logs endpoint uses Vault reference\n' \
                            "${COLOR_GREEN}" "${COLOR_RESET}"
                        ((passed += 1))
                    else
                        printf '%s[FAIL]%s OpenTelemetry access logs endpoint does not use Vault reference\n' \
                            "${COLOR_RED}" "${COLOR_RESET}"
                        ((failed += 1))
                    fi
                else
                    printf '%s[SKIP]%s OpenTelemetry access logs endpoint Vault reference check not required for %s\n' \
                        "${COLOR_YELLOW}" "${COLOR_RESET}" "${cp_type}"
                fi

                # Logs endpoint:
                # Vault reference is required only for on-prem.
                if [[ "${cp_type}" == "onprem" ]]; then
                    if [[ "${otel_logs_endpoint}" == *"{vault://"* ]]; then
                        printf '%s[PASS]%s OpenTelemetry logs endpoint uses Vault reference\n' \
                            "${COLOR_GREEN}" "${COLOR_RESET}"
                        ((passed += 1))
                    else
                        printf '%s[FAIL]%s OpenTelemetry logs endpoint does not use Vault reference\n' \
                            "${COLOR_RED}" "${COLOR_RESET}"
                        ((failed += 1))
                    fi
                else
                    printf '%s[SKIP]%s OpenTelemetry logs endpoint Vault reference check not required for %s\n' \
                        "${COLOR_YELLOW}" "${COLOR_RESET}" "${cp_type}"
                fi

                # Metrics endpoint must use Vault reference.
                if [[ "${otel_metrics_endpoint}" == *"{vault://"* ]]; then
                    printf '%s[PASS]%s OpenTelemetry metrics endpoint uses Vault reference\n' \
                        "${COLOR_GREEN}" "${COLOR_RESET}"
                    ((passed += 1))
                else
                    printf '%s[FAIL]%s OpenTelemetry metrics endpoint does not use Vault reference\n' \
                        "${COLOR_RED}" "${COLOR_RESET}"
                    ((failed += 1))
                fi

                # Traces endpoint must use Vault reference.
                if [[ "${otel_traces_endpoint}" == *"{vault://"* ]]; then
                    printf '%s[PASS]%s OpenTelemetry traces endpoint uses Vault reference\n' \
                        "${COLOR_GREEN}" "${COLOR_RESET}"
                    ((passed += 1))
                else
                    printf '%s[FAIL]%s OpenTelemetry traces endpoint does not use Vault reference\n' \
                        "${COLOR_RED}" "${COLOR_RESET}"
                    ((failed += 1))
                fi
            fi

            # ----------------------------------------------------------------
            # Rate Limiting Advanced global plugin configuration checks
            # ----------------------------------------------------------------
            rl_plugin="$(echo "${plugins_response}" | jq -c '
                .data[]?
                | select(.name == "rate-limiting-advanced")
                | select(
                    (.route == null) and
                    (.service == null) and
                    (.consumer == null) and
                    (.consumer_group == null)
                  )
            ' | head -n 1)"

            if [[ -z "${rl_plugin}" ]]; then
                printf '%s[FAIL]%s Global rate-limiting-advanced plugin not found\n' \
                    "${COLOR_RED}" "${COLOR_RESET}"
                ((failed += 1))
            else
                printf '%s[PASS]%s Global rate-limiting-advanced plugin found\n' \
                    "${COLOR_GREEN}" "${COLOR_RESET}"
                ((passed += 1))

                
                rl_strategy="$(echo "${rl_plugin}" | jq -r '.config.strategy // empty')"

                if [[ "${rl_strategy}" == "redis" ]]; then
                    printf '%s[PASS]%s Rate limiting strategy is redis\n' \
                        "${COLOR_GREEN}" "${COLOR_RESET}"
                    ((passed += 1))
                else
                    printf '%s[FAIL]%s Rate limiting strategy is not redis (found: %s)\n' \
                        "${COLOR_RED}" "${COLOR_RESET}" \
                        "${rl_strategy:-not configured}"
                    ((failed += 1))
                fi

                # Redis configuration must use Vault references for on-prem only.
                # Redis configuration must use Vault references for on-prem only.
                if [[ "${cp_type}" == "onprem" ]]; then

                    redis_values="$(echo "${rl_plugin}" | jq -r '
                        [
                            .config.redis.username,
                            .config.redis.password
                        ]
                        | .[]
                        | tostring
                    ')"

                    redis_index=0

                    while IFS= read -r value; do
                        case "${redis_index}" in
                            0)
                                field="Redis username"
                                ;;
                            1)
                                field="Redis password"
                                ;;
                            *)
                                break
                                ;;
                        esac

                        if [[ "${value}" == *"vault"* || "${value}" == *"Vault"* ]]; then
                            printf '%s[PASS]%s %s uses Vault reference\n' \
                                "${COLOR_GREEN}" "${COLOR_RESET}" "${field}"
                            ((passed += 1))
                        else
                            printf '%s[FAIL]%s %s does not use Vault reference\n' \
                                "${COLOR_RED}" "${COLOR_RESET}" "${field}"
                            ((failed += 1))
                        fi

                        ((redis_index += 1))
                    done <<< "${redis_values}"

                    # ------------------------------------------------------------
                    # Sentinel configuration checks
                    #
                    # These checks are required ONLY for ONPREM.
                    #
                    # sentinel_nodes is an array of objects:
                    # [
                    #   {
                    #     "host": "...",
                    #     "port": 26379
                    #   }
                    # ]
                    #
                    # sentinel_master is a string.
                    # sentinel_role must be one of:
                    # master, slave, any
                    # ------------------------------------------------------------

                    sentinel_nodes="$(echo "${rl_plugin}" | jq -c \
                        '.config.redis.sentinel_nodes // []')"

                    sentinel_master="$(echo "${rl_plugin}" | jq -r \
                        '.config.redis.sentinel_master // empty')"

                    sentinel_role="$(echo "${rl_plugin}" | jq -r \
                        '.config.redis.sentinel_role // empty')"

                    # ------------------------------------------------------------
                    # Sentinel nodes
                    # ------------------------------------------------------------
                    if jq -e '
                        type == "array" and
                        length > 0 and
                        all(.[]; type == "object")
                    ' <<< "${sentinel_nodes}" >/dev/null 2>&1; then

                        printf '%s[PASS]%s Rate limiting sentinel_nodes is configured\n' \
                            "${COLOR_GREEN}" "${COLOR_RESET}"
                        ((passed += 1))
                    else
                        printf '%s[FAIL]%s Rate limiting sentinel_nodes is not configured\n' \
                            "${COLOR_RED}" "${COLOR_RESET}"
                        ((failed += 1))
                    fi

                    # ------------------------------------------------------------
                    # Sentinel master
                    # ------------------------------------------------------------
                    if [[ -n "${sentinel_master}" && "${sentinel_master}" != "null" ]]; then

                        printf '%s[PASS]%s Rate limiting sentinel_master is configured\n' \
                            "${COLOR_GREEN}" "${COLOR_RESET}"
                        ((passed += 1))
                    else
                        printf '%s[FAIL]%s Rate limiting sentinel_master is not configured\n' \
                            "${COLOR_RED}" "${COLOR_RESET}"
                        ((failed += 1))
                    fi

                    # ------------------------------------------------------------
                    # Sentinel role
                    # ------------------------------------------------------------
                    if [[ "${sentinel_role}" == "master" ||
                        "${sentinel_role}" == "slave" ||
                        "${sentinel_role}" == "any" ]]; then

                        printf '%s[PASS]%s Rate limiting sentinel_role is configured (%s)\n' \
                            "${COLOR_GREEN}" "${COLOR_RESET}" "${sentinel_role}"
                        ((passed += 1))
                    else
                        printf '%s[FAIL]%s Rate limiting sentinel_role is not configured or invalid (found: %s)\n' \
                            "${COLOR_RED}" "${COLOR_RESET}" \
                            "${sentinel_role:-not configured}"
                        ((failed += 1))
                    fi

                else
                    printf '%s[SKIP]%s Redis configuration Vault reference and Sentinel checks not required for %s\n' \
                        "${COLOR_YELLOW}" "${COLOR_RESET}" "${cp_type}"
                fi
            fi

            return 0
        fi

        rm -f "${body}"
        if (( attempt < MAX_ATTEMPTS )); then
            sleep "${RETRY_SECONDS}"
        fi
    done

    printf '%s[FAIL]%s Global plugins (last HTTP %s)\n' \
        "${COLOR_RED}" "${COLOR_RESET}" "${code:-000}" >&2
    ((failed += 1))
    return 0
}

# Resource identifiers are supplied by Terraform output. Keep each entry as
# JSON while iterating and URI-encode it before adding it to a path. Parsing
# `@tsv` output with `read` can otherwise carry escaped/control characters
# into curl and cause its "bad/illegal format" error.
uri_path_segment() {
    jq -rn --arg value "$1" '$value | @uri'
}

cp_id="$(jq -er '.control_plane.id' <<<"${targets}")"
cp_group_id="$(jq -er '.control_plane_group.id' <<<"${targets}")"
system_account_id="$(jq -er '.system_account.id' <<<"${targets}")"

verify_get 'Control plane' \
    "${KONNECT_API_BASE}/v2/control-planes/${cp_id}" \
    "${cp_id}"

verify_get 'Control plane group' \
    "${KONNECT_API_BASE}/v2/control-planes/${cp_group_id}" \
    "${cp_group_id}"

verify_get 'Control plane group membership' \
    "${KONNECT_API_BASE}/v2/control-planes/${cp_group_id}/group-memberships"

verify_get 'System account' \
    "${KONNECT_GLOBAL_API_BASE}/v3/system-accounts/${system_account_id}" \
    "${system_account_id}"

verify_get 'System account role assignments' \
    "${KONNECT_GLOBAL_API_BASE}/v3/system-accounts/${system_account_id}/assigned-roles"

while IFS= read -r team; do
    team_key="$(jq -er '.key' <<<"${team}")"
    team_id="$(jq -er '.value.id | strings' <<<"${team}")"
    team_id_path="$(uri_path_segment "${team_id}")"

    verify_get \
        "Team ${team_key}" \
        "${KONNECT_GLOBAL_API_BASE}/v3/teams/${team_id_path}" \
        "${team_id}"
done < <(jq -c '.teams | to_entries[]' <<<"${targets}")

route_id="$(jq -er '.route.id' <<<"${targets}")"

verify_get \
    'Health-check route' \
    "${KONNECT_API_BASE}/v2/control-planes/${cp_id}/core-entities/routes/${route_id}" \
    "${route_id}"

global_plugins="$(jq -ec '.global_plugins' <<<"${targets}")"

verify_global_plugins \
    "${KONNECT_API_BASE}/v2/control-planes/${cp_id}/core-entities/plugins" \
    "${global_plugins}" \
    "${CP_TYPE}"

printf 'Verification summary: %s%d passed%s, %s%d failed%s.\n' \
    "${COLOR_GREEN}" "${passed}" "${COLOR_RESET}" \
    "${COLOR_RED}" "${failed}" "${COLOR_RESET}"

(( failed == 0 ))