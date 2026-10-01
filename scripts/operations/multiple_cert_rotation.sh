#!/bin/bash

# Exit immediately if any command fails
set -e

# Validate input using your requested format
[[ $# -eq 1 ]] || {
    echo "Usage: $0 <DAYS_OF_CERT_VALIDITY>"
    echo "Example: $0 365"
    exit 1
}

DAYS_ARG="$1"

echo "Step 1: Making the rotation script executable..."
chmod +x cert_rotation.sh

echo "Step 2: Verifying file permissions..."
ls -l cert_rotation.sh

echo "Step 3: Executing cert_rotation.sh for all combinations..."
echo "Days applied to all: $DAYS_ARG"
echo "--------------------------------------------------"

# --- DEV ---
echo ""
echo "=================================================="
echo "Running rotation for: ENV=dev | CP_TYPE=onprem | DAYS=$DAYS_ARG"
echo "=================================================="
bash cert_rotation.sh "dev" "onprem" "$DAYS_ARG"
echo "[✓] Finished: dev / onprem"

echo ""
echo "=================================================="
echo "Running rotation for: ENV=dev | CP_TYPE=gcloud | DAYS=$DAYS_ARG"
echo "=================================================="
bash cert_rotation.sh "dev" "gcloud" "$DAYS_ARG"
echo "[✓] Finished: dev / gcloud"

# --- UAT ---
echo ""
echo "=================================================="
echo "Running rotation for: ENV=uat | CP_TYPE=onprem | DAYS=$DAYS_ARG"
echo "=================================================="
bash cert_rotation.sh "uat" "onprem" "$DAYS_ARG"
echo "[✓] Finished: uat / onprem"

echo ""
echo "=================================================="
echo "Running rotation for: ENV=uat | CP_TYPE=gcloud | DAYS=$DAYS_ARG"
echo "=================================================="
bash cert_rotation.sh "uat" "gcloud" "$DAYS_ARG"
echo "[✓] Finished: uat / gcloud"

# --- PPD ---
echo ""
echo "=================================================="
echo "Running rotation for: ENV=ppd | CP_TYPE=onprem | DAYS=$DAYS_ARG"
echo "=================================================="
bash cert_rotation.sh "ppd" "onprem" "$DAYS_ARG"
echo "[✓] Finished: ppd / onprem"

echo ""
echo "=================================================="
echo "Running rotation for: ENV=ppd | CP_TYPE=gcloud | DAYS=$DAYS_ARG"
echo "=================================================="
bash cert_rotation.sh "ppd" "gcloud" "$DAYS_ARG"
echo "[✓] Finished: ppd / gcloud"

# --- PRD ---
echo ""
echo "=================================================="
echo "Running rotation for: ENV=prd | CP_TYPE=onprem | DAYS=$DAYS_ARG"
echo "=================================================="
bash cert_rotation.sh "prd" "onprem" "$DAYS_ARG"
echo "[✓] Finished: prd / onprem"

echo ""
echo "=================================================="
echo "Running rotation for: ENV=prd | CP_TYPE=gcloud | DAYS=$DAYS_ARG"
echo "=================================================="
bash cert_rotation.sh "prd" "gcloud" "$DAYS_ARG"
echo "[✓] Finished: prd / gcloud"

echo ""
echo "All certificate rotation combinations completed successfully!"