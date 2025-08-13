#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Uptime.com Data Export Script
# =============================================================================
# This script exports all monitoring data from uptime.com for migration to StatusCake
# 
# Prerequisites:
# - UPTIME_API_TOKEN environment variable set
# - jq installed for JSON processing
# - curl for API requests
#
# Usage: ./migration-from-uptime.sh
# =============================================================================

# Ensure we have required API token
: "${UPTIME_API_TOKEN:?Need to set UPTIME_API_TOKEN env var}"

# Configuration: Change this to match your uptime.com subaccount name
TARGET_SUBACCOUNT="Platform Services"

echo "=== UPTIME.COM DATA EXPORT ==="
echo "Exporting data for migration to StatusCake"
echo ""


# Step 1: Get all subaccounts and extract the pk where name is "Platform Services"
echo "Step 1: Finding subaccount..."
SUBACCOUNT_ID=$(curl -sS \
    -H "Authorization: Token $UPTIME_API_TOKEN" \
    "https://uptime.com/api/v1/auth/subaccounts/" \
    | jq -r --arg name "$TARGET_SUBACCOUNT" '.[] | select(.name == $name) | .pk')

if [[ -z "$SUBACCOUNT_ID" ]]; then
    echo "Subaccount '$TARGET_SUBACCOUNT' not found!" >&2
    exit 1
fi

echo "Using subaccount ID: $SUBACCOUNT_ID"
echo ""

# Step 2: Get all contacts for the subaccount
echo "Step 2: Fetching contacts..."
curl -sS \
  -H "Authorization: Token $UPTIME_API_TOKEN" \
  "https://uptime.com/api/v1/contacts/?subaccount=$SUBACCOUNT_ID" \
  > contacts.json

echo "Contacts exported to contacts.json"
echo "Contact count: $(jq '.results | length' contacts.json)"
echo ""

# Step 3: Fetch Integrations
echo "Step 3: Fetching integrations..."
curl -sS \
  -H "Authorization: Token $UPTIME_API_TOKEN" \
  "https://uptime.com/api/v1/integrations/?subaccount=$SUBACCOUNT_ID" \
  > integrations.json

echo "Integrations exported to integrations.json"
echo "Integration count: $(jq '.results | length' integrations.json)"
echo ""

# Step 4: Fetch all monitors/checks
echo "Step 4: Fetching monitors/checks..."
curl -sS \
  -H "Authorization: Token $UPTIME_API_TOKEN" \
  "https://uptime.com/api/v1/checks/?subaccount=$SUBACCOUNT_ID" \
  > monitors.json

echo "Monitors exported to monitors.json"
echo "Monitor count: $(jq '.results | length' monitors.json)"
echo ""

# Step 5: Create human-readable summary report
echo "Step 5: Generating summary report..."

echo "=== EXPORT SUMMARY ===" > export_summary.txt
echo "Export Date: $(date)" >> export_summary.txt
echo "Subaccount: $TARGET_SUBACCOUNT (ID: $SUBACCOUNT_ID)" >> export_summary.txt
echo "" >> export_summary.txt

echo "CONTACTS:" >> export_summary.txt
jq -r '.results[] | "- \(.name) (\(.email_list | join(", ")))"' contacts.json >> export_summary.txt
echo "" >> export_summary.txt

echo "INTEGRATIONS:" >> export_summary.txt
jq -r '.results[] | "- \(.name) (\(.integration_type)): \(.url)"' integrations.json >> export_summary.txt
echo "" >> export_summary.txt

echo "MONITORS:" >> export_summary.txt
jq -r '.results[] | "- \(.name) (\(.url)) - Interval: \(.interval_sec)s"' monitors.json >> export_summary.txt

echo "Summary report created: export_summary.txt"
echo ""

# Print quick overview
echo "=== QUICK OVERVIEW ==="
echo "Contacts: $(jq '.results | length' contacts.json)"
echo "Integrations: $(jq '.results | length' integrations.json)"  
echo "Monitors: $(jq '.results | length' monitors.json)"
echo ""
echo "Files created:"
echo "- contacts.json"
echo "- integrations.json"
echo "- monitors.json"
echo "- export_summary.txt"
echo ""
echo "Ready for StatusCake migration!"
