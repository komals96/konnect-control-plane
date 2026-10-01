#!/bin/bash

# Kong DP-CP mTLS Certificate Generation and Rotation Script
# ----------------------------------------------------------------
#
# Workflow:
#    1. Validate command-line arguments
#    2. Derive environment-specific settings
#    3. Check prerequisites
#    4. Fetch Konnect SAT from GCP Secret Manager
#    5. Generate self-signed ECDSA certificate
#    6. Validate certificate and private key
#    7. Fetch CPG ID from Konnect
#    8. Upload certificate to Konnect
#    9. Store certificate:
#        - onprem -> Bitbucket + Ansible Vault + Pull Request
#        - gcloud -> GCP Secret Manager
#   10. Cleanup temporary files and secrets
#
# ----------------------------------------------------------------

set -Ee -o pipefail

[[ $# -eq 3 ]] || {
    echo "Usage: $0 <ENV> <CP_TYPE> <DAYS_OF_CERT_VAILIDTY>"
    echo "Example: $0 dev onprem 365"
    exit 1
}

readonly ENV="$1"
readonly CP_TYPE="$2"
readonly DAYS="${3:-365}"

readonly KONNECT_REGION="https://us.api.konghq.com"
readonly BITBUCKET_WORKSPACE="oreillyauto"

WORK_DIR=""
CERT_FILE=""
KEY_FILE=""
VAULT_PASSWORD_FILE=""

PROJECT_PREFIX=""
PROJECT_ID=""

KONNECT_TOKEN=""
VAULT_PASSWORD=""

BITBUCKET_REPO=""
BITBUCKET_URL=""

# Using environment variables passed into the session
BITBUCKET_USERNAME="${BITBUCKET_USERNAME:-}"
BITBUCKET_TOKEN="${BITBUCKET_TOKEN:-}"

SOURCE_BRANCH=""
REPO_DIR=""
INVENTORY_DIR=""
ARCHIVE_DIR=""
TIMESTAMP=""

TARGET_BRANCH="main"
BITBUCKET_REPO="${BITBUCKET_REPO:-kong-onprem-dp-itg}"
KONNECT_UPLOAD_COMPLETED=false


# ----------------------------------------------------------------
# Logging
# ----------------------------------------------------------------

if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    RESET=$'\033[0m'
else
    RED=''
    GREEN=''
    RESET=''
fi


log_info() {
    printf "[INFO] %s\n" "$1"
}


log_success() {
    printf "${GREEN}[SUCCESS] %s${RESET}\n" "$1"
}


log_error() {
    printf "${RED}[ERROR] %s${RESET}\n" "$1" >&2
}


print_separator() {
    printf '%s\n' "------------------------------------------------------------------------------------"
}


# ----------------------------------------------------------------
# Cleanup
# Removes temporary files and clears sensitive variables.
# ----------------------------------------------------------------

cleanup() {

    log_info "Cleaning up..."

    unset KONNECT_TOKEN
    unset VAULT_PASSWORD
    unset BITBUCKET_TOKEN

    if [[ -n "${VAULT_PASSWORD_FILE}" && -f "${VAULT_PASSWORD_FILE}" ]]; then
        rm -f "${VAULT_PASSWORD_FILE}"
    fi

    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
    fi

    log_success "Cleanup completed."
    print_separator
}


trap cleanup EXIT


# ----------------------------------------------------------------
# Error handler
# Reports unexpected failures and highlights partial Konnect
# updates that may require manual remediation.
# ----------------------------------------------------------------

error_handler() {

    local exit_code=$?
    local line_number=$1

    log_error "Script failed at line ${line_number}."

    if [[ "${KONNECT_UPLOAD_COMPLETED}" == true ]]; then
        log_error "CRITICAL: Certificate was uploaded to Konnect, but the remaining workflow failed."
        log_error "Manual verification/remediation may be required.You may need to remove the newly created certificate from Konnect manually."
    fi

    exit "${exit_code}"
}


trap 'error_handler ${LINENO}' ERR


# ----------------------------------------------------------------
# Validate inputs and required environment variables.
# ----------------------------------------------------------------

validate_inputs() {

    log_info "[1/9] Validating inputs..."

    [[ "${ENV}" =~ ^(dev|uat|ppd|prd)$ ]] || {
        log_error "Invalid ENV. Supported values: dev, uat, ppd, prd."
        exit 1
    }

    [[ "${CP_TYPE}" =~ ^(onprem|gcloud)$ ]] || {
        log_error "Invalid CP_TYPE. Supported values: onprem, gcloud."
        exit 1
    }

    [[ "${DAYS}" =~ ^[0-9]+$ && "${DAYS}" -gt 0 ]] || {
        log_error "DAYS must be a positive integer."
        exit 1
    }

    if [[ "${CP_TYPE}" == "onprem" ]]; then

        [[ -n "${BITBUCKET_USERNAME}" ]] || {
            log_error "Environment variable BITBUCKET_USERNAME is not set."
            exit 1
        }

        [[ -n "${BITBUCKET_TOKEN}" ]] || {
            log_error "Environment variable BITBUCKET_TOKEN is not set."
            exit 1
        }
    fi

    log_success "Inputs validated."

    echo " "
    echo "Configuration Summary"
    echo "---------------------"
    echo "  Environment (ENV):                                        ${ENV}"
    echo "  Control Plane type (CP_TYPE):                             ${CP_TYPE}"
    echo "  Certificate Validity (DAYS):                              ${DAYS}"

    if [[ "${CP_TYPE}" == "onprem" ]]; then
        echo "  Bitbucket Workspace:                                      ${BITBUCKET_WORKSPACE}"
        echo "  Bitbucket Repository:                                     ${BITBUCKET_REPO}"
        echo "  Target Branch:                                            ${TARGET_BRANCH}"
        echo "  Bitbucket Username (BITBUCKET_USERNAME):                  ${BITBUCKET_USERNAME}"
    fi

    print_separator
}


# ----------------------------------------------------------------
# Derive environment-specific GCP and Bitbucket settings.
# ----------------------------------------------------------------

derive_environment_settings() {

    log_info "[2/9] Deriving environment settings..."

    if [[ "${CP_TYPE}" == "onprem" ]]; then
        BITBUCKET_URL="git@bitbucket.org:${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO}.git"

        TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
        SOURCE_BRANCH="release-branch-${TIMESTAMP}"
    fi

    case "${ENV}" in
        dev|uat)
            PROJECT_PREFIX="nprd"
            ;;

        ppd)
            PROJECT_PREFIX="pprd"
            ;;

        prd)
            PROJECT_PREFIX="prod"
            ;;

        *)
            log_error "Unsupported environment."
            exit 1
            ;;
    esac

    PROJECT_ID="us-${PROJECT_PREFIX}-itg-api-kong-01"

    log_success "Environment settings derived."

    echo " "
    echo "Derived Settings"
    echo "----------------"

    echo "  GCP Project ID:                                           ${PROJECT_ID}"

    if [[ "${CP_TYPE}" == "onprem" ]]; then
        echo "  Bitbucket URL:                                            ${BITBUCKET_URL}"
        echo "  Bitbucket Username:                                       ${BITBUCKET_USERNAME}"
        echo "  Source Branch:                                            ${SOURCE_BRANCH}"
    fi

    print_separator
}


# ----------------------------------------------------------------
# Check required command-line tools.
# ----------------------------------------------------------------

check_prerequisites() {

    log_info "[3/9] Checking prerequisites..."

    local tools=(
        openssl
        curl
        jq
        gcloud
    )

    if [[ "${CP_TYPE}" == "onprem" ]]; then
        tools+=(
            git
            ansible-vault
        )
    fi

    local tool

    for tool in "${tools[@]}"; do

        if ! command -v "${tool}" &>/dev/null; then
            log_error "${tool} not installed."
            exit 1
        fi

        echo "  [✓] ${tool}"
    done

    log_success "Prerequisites check completed."
    print_separator
}


# ----------------------------------------------------------------
# Fetch Konnect Service Account Token from GCP Secret Manager.
# ----------------------------------------------------------------

fetch_konnect_token() {

    log_info "[4/9] Fetching Konnect SAT from GCP Secret Manager..."

    local secret_name="us-prod-itg-api-kong-konnect-platform-ops-sat-info"

    KONNECT_TOKEN=$(
        gcloud secrets versions access latest \
            --project="us-prod-itg-api-kong-01" \
            --secret="${secret_name}" \
        | jq -r '.token'
    )

    [[ -n "${KONNECT_TOKEN}" && "${KONNECT_TOKEN}" != "null" ]] || {
        log_error "Failed to fetch Konnect SAT."
        exit 1
    }

    log_success "Konnect SAT fetched."
    print_separator
}


# ----------------------------------------------------------------
# Create temporary working directory for certificates,
# repository clone and temporary secrets.
# ----------------------------------------------------------------

create_workdir() {

    log_info "Creating temporary working directory..."

    WORK_DIR="$(mktemp -d)"

    chmod 700 "${WORK_DIR}"

    CERT_FILE="${WORK_DIR}/tls.crt"
    KEY_FILE="${WORK_DIR}/tls.key"
    VAULT_PASSWORD_FILE="${WORK_DIR}/vault_password"

    log_success "Temporary working directory created."
    print_separator
}


# ----------------------------------------------------------------
# Generate ECDSA P-256 self-signed certificate.
# ----------------------------------------------------------------

generate_certificate() {

    log_info "[5/9] Generating OpenSSL self-signed certificate..."

    local subject_cn="konnect-${ENV}-${CP_TYPE}-cpg"
    local openssl_cfg="${WORK_DIR}/openssl.cnf"

    cat > "${openssl_cfg}" <<EOF
[ req ]
prompt = no
distinguished_name = req_dn
x509_extensions = v3_ext

[ req_dn ]
C = US
CN = ${subject_cn}

[ v3_ext ]
basicConstraints = critical,CA:FALSE
keyUsage = keyCertSign,cRLSign
extendedKeyUsage = serverAuth,clientAuth
subjectKeyIdentifier = hash
EOF

    openssl ecparam \
        -name prime256v1 \
        -genkey \
        -noout \
    | openssl pkcs8 \
        -topk8 \
        -nocrypt \
        -out "${KEY_FILE}"

    chmod 600 "${KEY_FILE}"

    openssl req \
        -new \
        -x509 \
        -sha512 \
        -days "${DAYS}" \
        -key "${KEY_FILE}" \
        -out "${CERT_FILE}" \
        -config "${openssl_cfg}" \
        -extensions v3_ext

    chmod 600 "${CERT_FILE}"

    [[ -f "${CERT_FILE}" && -f "${KEY_FILE}" ]] || {
        log_error "Certificate generation failed."
        exit 1
    }

    log_success "Certificate generated."

    echo " "
    echo "Certificate Details"
    echo "-------------------"

    openssl x509 \
        -in "${CERT_FILE}" \
        -noout \
        -subject \
        -dates

    print_separator
}


# ----------------------------------------------------------------
# Validate that the generated certificate and private key match.
# ----------------------------------------------------------------

validate_certificate() {

    log_info "[6/9] Validating generated certificate..."

    local cert_pubkey
    local key_pubkey

    cert_pubkey="$(
        openssl x509 \
            -in "${CERT_FILE}" \
            -pubkey \
            -noout \
        | openssl pkey \
            -pubin \
            -outform DER \
        | sha256sum
    )"

    key_pubkey="$(
        openssl pkey \
            -in "${KEY_FILE}" \
            -pubout \
        | openssl pkey \
            -pubin \
            -outform DER \
        | sha256sum
    )"

    [[ "${cert_pubkey}" == "${key_pubkey}" ]] || {
        log_error "Certificate and private key do not match."
        exit 1
    }

    log_success "Certificate and private key validation passed."
    print_separator
}


# ----------------------------------------------------------------
# Fetch the Konnect Control Plane Group ID.
# ----------------------------------------------------------------

get_cpg_id() {
    local cpg_name="${ENV}-${CP_TYPE}-cpg"
    local response_file
    local http_status

    response_file="$(mktemp)"
    trap 'rm -f "${response_file}"' RETURN

    http_status="$(
        curl -sS \
            -o "${response_file}" \
            -w '%{http_code}' \
            --request GET \
            --url "${KONNECT_REGION}/v2/control-planes?filter%5Bname%5D=${cpg_name}" \
            --header "Authorization: Bearer ${KONNECT_TOKEN}" \
            --header 'Accept: application/json'
    )"

    if [[ "${http_status}" -lt 200 || "${http_status}" -ge 300 ]]; then
        log_error "Failed to fetch control plane ID for ${cpg_name}."
        log_error "HTTP Status: ${http_status}"

        if [[ -s "${response_file}" ]]; then
            log_error "Konnect API response:"
            cat "${response_file}" >&2
            echo >&2
        fi

        return 1
    fi

    jq -r '.data[0].id' "${response_file}"
}


# ----------------------------------------------------------------
# Upload generated certificate to the Konnect CPG.
# ----------------------------------------------------------------

upload_certificate() {

    log_info "[8/9] Uploading certificate to Konnect..."

    local cpg_name="${ENV}-${CP_TYPE}-cpg"
    local cpg_id="$1"
    local payload

    payload="$(jq -Rs '{cert:.}' "${CERT_FILE}")"

    curl -sS \
        --fail-with-body \
        --request POST \
        --url "${KONNECT_REGION}/v2/control-planes/${cpg_id}/dp-client-certificates" \
        --header "Accept: application/json" \
        --header "Authorization: Bearer ${KONNECT_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "${payload}" \
        > /dev/null

    KONNECT_UPLOAD_COMPLETED=true

    log_success "Certificate uploaded to Konnect for CPG ${cpg_name}."
    print_separator
}


# ----------------------------------------------------------------
# Clone the Bitbucket repository.
# ----------------------------------------------------------------

clone_repository() {

    log_info "Cloning Bitbucket repository ${BITBUCKET_REPO}..."

    REPO_DIR="${WORK_DIR}/${BITBUCKET_REPO}"

    git clone \
        --quiet \
        "${BITBUCKET_URL}" \
        "${REPO_DIR}" || {
            log_error "Failed to clone Bitbucket repository."
            exit 1
        }

    log_success "Repository ${BITBUCKET_REPO} cloned."
    print_separator
}


# ----------------------------------------------------------------
# Update target branch and create a unique release branch.
# ----------------------------------------------------------------

prepare_repository() {

    log_info "Preparing Bitbucket repository..."

    cd "${REPO_DIR}"

    git fetch origin "${TARGET_BRANCH}" >/dev/null 2>&1 || {
        log_error "Failed to fetch target branch '${TARGET_BRANCH}'."
        exit 1
    }

    git checkout "${TARGET_BRANCH}" >/dev/null 2>&1 || {
        log_error "Failed to checkout target branch '${TARGET_BRANCH}'."
        exit 1
    }

    git pull --quiet --ff-only origin "${TARGET_BRANCH}" >/dev/null 2>&1 || {
        log_error "Failed to update target branch '${TARGET_BRANCH}'."
        exit 1
    }

    git checkout -b "${SOURCE_BRANCH}" >/dev/null 2>&1 || {
        log_error "Failed to create source branch '${SOURCE_BRANCH}'."
        exit 1
    }

    log_success "Created source branch '${SOURCE_BRANCH}' from '${TARGET_BRANCH}'."
    print_separator
}


# ----------------------------------------------------------------
# Archive existing certificates before replacing them.
# ----------------------------------------------------------------

archive_existing_certificates() {

    INVENTORY_DIR="${REPO_DIR}/inventory/${ENV}/certificates"

    mkdir -p "${INVENTORY_DIR}"

    TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

    if [[ -f "${INVENTORY_DIR}/tls.crt" || -f "${INVENTORY_DIR}/tls.key" ]]; then

        if [[ ! -f "${INVENTORY_DIR}/tls.crt" || ! -f "${INVENTORY_DIR}/tls.key" ]]; then
            log_error "Existing certificate and private key are not both present."
            exit 1
        fi

        log_info "Archiving existing certificates..."

        ARCHIVE_DIR="${INVENTORY_DIR}/archives/${TIMESTAMP}"

        mkdir -p "${ARCHIVE_DIR}"

        cp "${INVENTORY_DIR}/tls.crt" "${ARCHIVE_DIR}/"
        cp "${INVENTORY_DIR}/tls.key" "${ARCHIVE_DIR}/"

        log_success "Existing certificates archived."
        print_separator

    else

        log_info "No existing certificates found. Archive not required."
        print_separator
    fi
}


# ----------------------------------------------------------------
# Fetch Ansible Vault password from GCP Secret Manager.
# ----------------------------------------------------------------

fetch_vault_password() {

    log_info "Fetching Ansible Vault Password from GCP Secret Manager..."

    local secret_name="us-${PROJECT_PREFIX}-itg-api-kong-ansible-vault-pwd"

    VAULT_PASSWORD=$(
        gcloud secrets versions access latest \
            --project="${PROJECT_ID}" \
            --secret="${secret_name}"
    )

    [[ -n "${VAULT_PASSWORD}" ]] || {
        log_error "Failed to fetch Vault Password."
        exit 1
    }

    printf '%s' "${VAULT_PASSWORD}" > "${VAULT_PASSWORD_FILE}"
    chmod 600 "${VAULT_PASSWORD_FILE}"

    log_success "Ansible Vault Password fetched."
    print_separator
}


# ----------------------------------------------------------------
# Copy generated certificates into the repository and encrypt them
# using Ansible Vault.
# ----------------------------------------------------------------

encrypt_certificates() {

    log_info "Encrypting certificates using Ansible Vault..."

    cp "${CERT_FILE}" "${INVENTORY_DIR}/tls.crt"
    cp "${KEY_FILE}" "${INVENTORY_DIR}/tls.key"

    chmod 600 \
        "${INVENTORY_DIR}/tls.crt" \
        "${INVENTORY_DIR}/tls.key"

    ansible-vault encrypt \
        "${INVENTORY_DIR}/tls.crt" \
        --vault-password-file "${VAULT_PASSWORD_FILE}" || {
            log_error "Failed to encrypt tls.crt."
            exit 1
        }

    ansible-vault encrypt \
        "${INVENTORY_DIR}/tls.key" \
        --vault-password-file "${VAULT_PASSWORD_FILE}" || {
            log_error "Failed to encrypt tls.key."
            exit 1
        }

    log_success "Certificates encrypted."
    print_separator
}


# ----------------------------------------------------------------
# Commit certificate changes and push the release branch.
# ----------------------------------------------------------------

commit_and_push() {

    log_info "Committing changes..."

    cd "${REPO_DIR}"

    git add "inventory/${ENV}" || {
        log_error "Failed to stage certificate changes."
        exit 1
    }

    if git diff --cached --quiet; then
        log_error "No changes detected after certificate update."
        exit 1
    fi

    git config user.name "${BITBUCKET_USERNAME%%@*}"
    git config user.email "${BITBUCKET_USERNAME}"

    git commit \
        -q \
        -m "Rotate mTLS certificate (${ENV})." || {
            log_error "Failed to create Git commit."
            exit 1
        }

    git push \
        -q \
        origin "${SOURCE_BRANCH}" >/dev/null 2>&1 || {
            log_error "Failed to push branch '${SOURCE_BRANCH}'."
            exit 1
        }

    log_success "Changes pushed to branch '${SOURCE_BRANCH}'."
    print_separator
}


# ----------------------------------------------------------------
# Check whether an open Pull Request already exists for the
# source/target branch pair.
# ----------------------------------------------------------------

check_existing_pr() {

    log_info "Checking for existing Pull Request..."

    local response
    local pr_count

    response=$(
        curl -fsS \
            -G \
            -u "${BITBUCKET_USERNAME}:${BITBUCKET_TOKEN}" \
            --data-urlencode "q=state=\"OPEN\" AND source.branch.name=\"${SOURCE_BRANCH}\" AND destination.branch.name=\"${TARGET_BRANCH}\"" \
            "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO}/pullrequests"
    ) || {
        log_error "Failed to query Bitbucket Pull Requests."
        exit 1
    }

    pr_count="$(jq '.size' <<< "${response}")"

    [[ "${pr_count}" =~ ^[0-9]+$ ]] || {
        log_error "Unable to determine existing Pull Request count."
        exit 1
    }

    [[ "${pr_count}" -eq 0 ]]
}


# ----------------------------------------------------------------
# Create a Pull Request from the release branch to the target branch.
# ----------------------------------------------------------------

create_pull_request() {

    log_info "Creating Pull Request..."

    local response

    response=$(
        curl -fsS \
            -u "${BITBUCKET_USERNAME}:${BITBUCKET_TOKEN}" \
            -H "Content-Type: application/json" \
            -X POST \
            "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_WORKSPACE}/${BITBUCKET_REPO}/pullrequests" \
            -d @- <<EOF
{
  "title": "Rotate mTLS certificate (${ENV})",
  "description": "Automated mTLS certificate rotation for the ${ENV} environment, executed by ${BITBUCKET_USERNAME}. Please review and merge to apply updates.",
  "source": {
    "branch": {
      "name": "${SOURCE_BRANCH}"
    }
  },
  "destination": {
    "branch": {
      "name": "${TARGET_BRANCH}"
    }
  },
  "close_source_branch": false
}
EOF
    ) || {
        log_error "Failed to create Pull Request."
        exit 1
    }

    local pr_url

    pr_url="$(jq -r '.links.html.href // empty' <<< "${response}")"

    if [[ -n "${pr_url}" ]]; then
        log_success "Pull Request created: ${pr_url}"
    else
        log_success "Pull Request created."
    fi

    print_separator
}


# ----------------------------------------------------------------
# Store certificate and key in Bitbucket for onprem.
# ----------------------------------------------------------------

store_in_bitbucket() {

    clone_repository
    prepare_repository
    archive_existing_certificates
    fetch_vault_password
    encrypt_certificates
    commit_and_push

    if check_existing_pr; then
        create_pull_request
    else
        log_info "Open Pull Request already exists."
        print_separator
    fi
}


# ----------------------------------------------------------------
# Store certificate and key in GCP Secret Manager. Disable previous secret version.
# ----------------------------------------------------------------

store_in_gcp() {

    log_info "Uploading certificate to GCP Secret Manager..."
    echo " "

    local cert_secret="us-${PROJECT_PREFIX}-itg-api-kong-konnect-tls-cert-${ENV}"
    local key_secret="us-${PROJECT_PREFIX}-itg-api-kong-konnect-tls-key-${ENV}"

    local new_cert_version
    new_cert_version=$(
        gcloud secrets versions add "${cert_secret}" \
            --project="${PROJECT_ID}" \
            --data-file="${CERT_FILE}" \
            --format="get(name)"
    ) || {
        log_error "Failed to store certificate in GCP Secret Manager."
        exit 1
    }

    local new_cert_id
    new_cert_id=$(basename "${new_cert_version}")

    for v in $(gcloud secrets versions list "${cert_secret}" \
        --project="${PROJECT_ID}" \
        --filter="state=ENABLED" \
        --format="value(name)"); do

        local version_id
        version_id=$(basename "${v}")

        if [[ "${version_id}" -ne "${new_cert_id}" ]]; then
            log_info "Disabling old certificate version (${version_id})..."
            gcloud secrets versions disable "${version_id}" \
                --secret="${cert_secret}" \
                --project="${PROJECT_ID}" --quiet || true
        fi
    done

    echo " "

    local new_key_version
    new_key_version=$(
        gcloud secrets versions add "${key_secret}" \
            --project="${PROJECT_ID}" \
            --data-file="${KEY_FILE}" \
            --format="get(name)"
    ) || {
        log_error "Failed to store private key in GCP Secret Manager."
        exit 1
    }

    local new_key_id
    new_key_id=$(basename "${new_key_version}")

    for v in $(gcloud secrets versions list "${key_secret}" \
        --project="${PROJECT_ID}" \
        --filter="state=ENABLED" \
        --format="value(name)"); do

        local version_id
        version_id=$(basename "${v}")

        if [[ "${version_id}" -ne "${new_key_id}" ]]; then
            log_info "Disabling old private key version (${version_id})..."
            gcloud secrets versions disable "${version_id}" \
                --secret="${key_secret}" \
                --project="${PROJECT_ID}" --quiet || true
        fi
    done

    echo " "

    log_success "Certificate stored in GCP Secret Manager and previous versions disabled."
    print_separator
}


# ----------------------------------------------------------------
# Select certificate storage mechanism based on CP_TYPE.
# ----------------------------------------------------------------

store_certificate() {

    if [[ "${CP_TYPE}" == "onprem" ]]; then
        log_info "[9/9] Proceeding to store certificate in Bitbucket..."
        print_separator
        store_in_bitbucket
    else
        log_info "[9/9] Proceeding to store certificate in GCP Secret Manager..."
        print_separator
        store_in_gcp
    fi
}


# ----------------------------------------------------------------
# Main workflow.
# ----------------------------------------------------------------

main() {

    print_separator
    echo "Kong DP-CP mTLS Certificate Generation Automation"
    echo "Executed at $(date)"
    print_separator

    log_info "Starting workflow..."
    print_separator

    validate_inputs
    derive_environment_settings
    check_prerequisites
    create_workdir
    fetch_konnect_token
    generate_certificate
    validate_certificate

    local cpg_id
    local cpg_name="${ENV}-${CP_TYPE}-cpg"
    log_info "[7/9] Fetching ID of CPG ${cpg_name}..."
    cpg_id="$(get_cpg_id)"

    [[ -n "${cpg_id}" && "${cpg_id}" != "null" ]] || {
        log_error "Unable to fetch CPG ID."
        exit 1
    }

    log_success "CPG ID retrieved successfully."
    print_separator

    upload_certificate "${cpg_id}"
    store_certificate

    log_success "Workflow completed successfully."
    print_separator
}


main "$@"