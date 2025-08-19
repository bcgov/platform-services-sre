#!/bin/bash

set -euo pipefail

# StatusCake Resource Fetcher - Simple Version
# This script fetches contact groups and uptime checks from StatusCake API
# Requires: STATUSCAKE_API_TOKEN environment variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to log errors
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to log success
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if API token is provided
if [[ -z "${STATUSCAKE_API_TOKEN:-}" ]]; then
    log_error "STATUSCAKE_API_TOKEN environment variable is required"
    echo "Usage: export STATUSCAKE_API_TOKEN=\"your_token_here\" && $0"
    exit 1
fi

# Function to fetch and display resources
fetch_and_display_resource() {
    local base_endpoint="$1"
    local resource_name="$2"
    local limit="${3:-100}"  # Default limit
    
    log_message "Fetching $resource_name..."
    
    local page=1
    local total_items=0
    local all_data="[]"
    
    while true; do
        local endpoint="${base_endpoint}?page=${page}&limit=${limit}"
        
        response=$(curl -sS -w "%{http_code}" \
            -H "Authorization: Bearer $STATUSCAKE_API_TOKEN" \
            "https://api.statuscake.com/v1/$endpoint" 2>/dev/null)
        
        http_code="${response: -3}"
        body="${response%???}"
        
        if [[ "$http_code" != "200" ]]; then
            log_error "Failed to fetch $resource_name page $page (HTTP $http_code): $body"
            return 1
        fi
        
        # Parse response
        local page_data=$(echo "$body" | jq '.data // []' 2>/dev/null)
        local page_count=$(echo "$page_data" | jq 'length' 2>/dev/null || echo "0")
        
        if [[ "$page_count" -eq 0 ]]; then
            break
        fi
        
        # Merge data
        all_data=$(echo "$all_data" "$page_data" | jq -s 'add' 2>/dev/null)
        total_items=$((total_items + page_count))
        
        # Check if we got less than the limit (last page)
        if [[ "$page_count" -lt "$limit" ]]; then
            break
        fi
        
        page=$((page + 1))
    done
    
    if [[ "$total_items" -gt 0 ]]; then
        log_success "$resource_name found: $total_items items"
        echo ""
        
        # Display the data in a formatted way
        if [[ "$resource_name" == "Contact Groups" ]]; then
            echo -e "${CYAN}=== CONTACT GROUPS ===${NC}"
            echo "$all_data" | jq -r '.[] | "ID: \(.id) | Name: \(.name) | Email: \(.email_addresses // [] | join(", ")) | Mobile: \(.mobile_numbers // [] | join(", ")) | Webhooks: \(.webhooks // [] | length)"'
        elif [[ "$resource_name" == "Uptime Checks" ]]; then
            echo -e "${CYAN}=== UPTIME CHECKS ===${NC}"
            echo "$all_data" | jq -r '.[] | "ID: \(.id) | Name: \(.name) | URL: \(.website_url) | Status: \(.status) | Check Rate: \(.check_rate)s | Contact Groups: \(.contact_groups // [] | join(", "))"'
        fi
        echo ""
        return 0
    else
        log_message "No $resource_name found"
        return 1
    fi
}

# Main execution
echo -e "${YELLOW}StatusCake Resource Summary${NC}"
echo "=========================="
echo ""

# 1. Contact Groups
fetch_and_display_resource "contact-groups" "Contact Groups"

# 2. Uptime Checks  
fetch_and_display_resource "uptime" "Uptime Checks"

log_success "Resource fetch completed!" 