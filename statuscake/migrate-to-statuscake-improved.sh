#!/bin/bash
set -euo pipefail

# =============================================================================
# StatusCake Migration Script
# =============================================================================
# This script imports monitoring data from uptime.com JSON files into StatusCake
# 
# Prerequisites:
# - STATUSCAKE_API_TOKEN environment variable set (for target workspace)
# - JSON files from migration-from-uptime.sh (contacts.json, monitors.json, etc.)
# - jq installed for JSON processing
# - curl for API requests
#
# Features:
# - Creates contact groups with email/SMS settings
# - Creates uptime checks with Toronto region monitoring
# - Handles plan limits gracefully
# - Provides detailed logging and error handling
#
# Usage: ./migrate-to-statuscake-improved.sh
# =============================================================================

# Ensure we have required API token for StatusCake
: "${STATUSCAKE_API_TOKEN:?Need to set STATUSCAKE_API_TOKEN env var}"

# Check if required JSON files exist
for file in contacts.json integrations.json monitors.json; do
    if [[ ! -f "$file" ]]; then
        echo "Error: $file not found. Please run migration-from-uptime.sh first." >&2
        exit 1
    fi
done

echo "=== STATUSCAKE MIGRATION ==="
echo "Migrating uptime.com data to StatusCake"
echo ""

# Configuration
MAX_RETRIES=3
RETRY_DELAY=2

# Create log file for tracking created resources
LOG_FILE="statuscake_migration_improved.log"
echo "Migration started at $(date)" > "$LOG_FILE"

# Arrays to track created resources
declare -a CREATED_CONTACT_GROUPS=()
declare -a CREATED_UPTIME_CHECKS=()
declare -a FAILED_CONTACT_GROUPS=()
declare -a FAILED_UPTIME_CHECKS=()

# Function to log and display messages
log_message() {
    echo "$1" >&2
    echo "$1" >> "$LOG_FILE"
}

# Function to check if contact group name exists
check_contact_group_exists() {
    local name="$1"
    local response
    response=$(curl -sS -w "%{http_code}" \
        -H "Authorization: Bearer $STATUSCAKE_API_TOKEN" \
        "https://api.statuscake.com/v1/contact-groups" 2>/dev/null)
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [[ "$http_code" == "200" ]]; then
        echo "$body" | jq -r --arg name "$name" '.data[]? | select(.name == $name) | .id' | head -1
    fi
}

# Function to create contact group in StatusCake with better error handling
create_contact_group_improved() {
    local name="$1"
    local emails="$2"
    local sms_numbers="$3"
    local webhook_url="$4"
    local contact_type="$5"
    
    # Check if contact group already exists
    local existing_id
    existing_id=$(check_contact_group_exists "$name")
    if [[ -n "$existing_id" ]]; then
        log_message "ℹ️  Contact group '$name' already exists with ID: $existing_id"
        CREATED_CONTACT_GROUPS+=("$existing_id:$name:$contact_type:existing")
        echo "$existing_id"
        return
    fi
    
    log_message "Creating contact group: $name ($contact_type)"
    
    # Prepare form data with proper URL encoding
    local form_data=""
    form_data+="name=$(printf '%s' "$name" | sed 's/ /%20/g' | sed 's/&/%26/g')"
    
    # Add email addresses if they exist
    if [[ -n "$emails" && "$emails" != "null" ]]; then
        IFS=',' read -ra EMAIL_ARRAY <<< "$emails"
        for email in "${EMAIL_ARRAY[@]}"; do
            email=$(echo "$email" | tr -d ' ')
            if [[ -n "$email" ]]; then
                form_data+="&email_addresses[]=$(printf '%s' "$email" | sed 's/@/%40/g')"
            fi
        done
    fi
    
    # Add SMS numbers if they exist  
    if [[ -n "$sms_numbers" && "$sms_numbers" != "null" ]]; then
        IFS=',' read -ra SMS_ARRAY <<< "$sms_numbers"
        for sms in "${SMS_ARRAY[@]}"; do
            sms=$(echo "$sms" | tr -d ' ')
            if [[ -n "$sms" ]]; then
                form_data+="&mobile_numbers[]=$(printf '%s' "$sms" | sed 's/+/%2B/g')"
            fi
        done
    fi
    
    # Add webhook URL if it exists
    if [[ -n "$webhook_url" && "$webhook_url" != "null" && "$webhook_url" != "PLACEHOLDER" ]]; then
        form_data+="&integrations[webhook]=$(printf '%s' "$webhook_url" | sed 's/:/%3A/g' | sed 's/\//%2F/g')"
    elif [[ "$webhook_url" == "PLACEHOLDER" ]]; then
        # Skip webhook for now - user will add manually
        log_message "⚠️  Skipping webhook for '$name' - will need manual setup"
    fi
    
    # Create the contact group with retry logic
    local attempt=1
    while [[ $attempt -le $MAX_RETRIES ]]; do
        local response
        response=$(curl -sS -w "%{http_code}" \
            -X POST \
            -H "Authorization: Bearer $STATUSCAKE_API_TOKEN" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "$form_data" \
            "https://api.statuscake.com/v1/contact-groups" 2>/dev/null)
        
        local http_code="${response: -3}"
        local body="${response%???}"
        
        if [[ "$http_code" == "201" ]]; then
            local contact_group_id
            contact_group_id=$(echo "$body" | jq -r '.data.new_id')
            log_message "✅ Contact group created with ID: $contact_group_id"
            CREATED_CONTACT_GROUPS+=("$contact_group_id:$name:$contact_type:created")
            echo "$contact_group_id"
            return
        elif [[ "$http_code" == "400" ]]; then
            log_message "❌ Failed to create contact group '$name' (HTTP $http_code)"
            log_message "   Response body: $body"
            FAILED_CONTACT_GROUPS+=("$name:$body")
            return
        else
            log_message "⚠️  Attempt $attempt failed for contact group '$name' (HTTP $http_code)"
            log_message "   Response body: $body"
            log_message "   Form data sent: $form_data"
            if [[ $attempt -lt $MAX_RETRIES ]]; then
                log_message "   Retrying in ${RETRY_DELAY}s..."
                sleep $RETRY_DELAY
            fi
        fi
        
        ((attempt++))
    done
    
    log_message "❌ Failed to create contact group '$name' after $MAX_RETRIES attempts"
    FAILED_CONTACT_GROUPS+=("$name:Max retries exceeded")
}

# Function to convert uptime.com interval to StatusCake check_rate
convert_interval_to_check_rate() {
    local interval_sec="$1"
    
    # Handle null or empty values - default to 5 minutes
    if [[ -z "$interval_sec" || "$interval_sec" == "null" ]]; then
        echo "300"
        return
    fi
    
    # StatusCake check_rate values: 0, 30, 60, 300, 900, 1800, 3600
    # Note: 600 (10 min) is not a valid StatusCake interval
    # Map uptime.com intervals to closest StatusCake values
    if [[ "$interval_sec" -le 30 ]]; then
        echo "30"
    elif [[ "$interval_sec" -le 60 ]]; then
        echo "60" 
    elif [[ "$interval_sec" -le 300 ]]; then
        echo "300"
    elif [[ "$interval_sec" -le 900 ]]; then
        echo "900"  # 15 minutes - closest to 10 minutes
    elif [[ "$interval_sec" -le 1800 ]]; then
        echo "1800"
    else
        echo "3600"
    fi
}

# Function to get current uptime check count
get_current_check_count() {
    local response
    response=$(curl -sS -w "%{http_code}" \
        -H "Authorization: Bearer $STATUSCAKE_API_TOKEN" \
        "https://api.statuscake.com/v1/uptime" 2>/dev/null)
    
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [[ "$http_code" == "200" ]]; then
        echo "$body" | jq '.data | length'
    else
        echo "0"
    fi
}

# Check current status
echo "🔍 Checking current StatusCake status..."
current_check_count=$(get_current_check_count)
log_message "Current uptime checks: $current_check_count"

# Count how many monitors we want to migrate
total_monitors=$(jq '.results | length' monitors.json)
log_message "Monitors to migrate: $total_monitors"

if [[ $((current_check_count + total_monitors)) -gt 50 ]]; then
    echo ""
    echo "⚠️  WARNING: You currently have $current_check_count uptime checks."
    echo "   Adding $total_monitors more would likely exceed your plan limits."
    echo "   StatusCake will stop creating checks when limit is reached."
    echo "   Continuing anyway..."
    echo ""
fi

# Step 1: Create contact groups based on uptime.com contacts and integrations
echo "Step 1: Creating contact groups..."

# Create a mapping of integration names to URLs
declare -A INTEGRATION_URLS
while IFS= read -r line; do
    name=$(echo "$line" | jq -r '.name')
    url=$(echo "$line" | jq -r '.url')
    INTEGRATION_URLS["$name"]="$url"
done < <(jq -c '.results[]' integrations.json)

# Create contact groups from uptime.com contacts
declare -A CONTACT_GROUP_MAP
declare -A PLACEHOLDER_CONTACTS
while IFS= read -r line; do
    name=$(echo "$line" | jq -r '.name')
    emails=$(echo "$line" | jq -r '.email_list | join(",")')
    sms_numbers=$(echo "$line" | jq -r '.sms_list | join(",")')
    
    # Get integrations array
    integrations_array=$(echo "$line" | jq -r '.integrations[]' 2>/dev/null || echo "")
    integration_count=$(echo "$line" | jq -r '.integrations | length')
    
    # Determine contact type and webhook handling
    contact_type=""
    webhook_url=""
    
    if [[ "$integration_count" -eq 0 ]]; then
        # Type 1: Simple contact (email/SMS only)
        contact_type="Email/SMS Only"
        webhook_url=""
    elif [[ "$integration_count" -eq 1 ]]; then
        # Type 2: Single integration contact
        contact_type="Single Integration"
        integration_name=$(echo "$integrations_array" | head -n1)
        # Don't use uptime.com URLs - they're not actual webhook endpoints
        webhook_url="PLACEHOLDER" 
        PLACEHOLDER_CONTACTS["$name"]="$integration_name"
    else
        # Type 3: Multiple integrations contact
        contact_type="Multiple Integrations"
        webhook_url="PLACEHOLDER"
        # Store all integration names for this contact
        all_integrations=$(echo "$line" | jq -r '.integrations | join(", ")')
        PLACEHOLDER_CONTACTS["$name"]="$all_integrations"
    fi
    
    log_message "Processing contact '$name': $contact_type (Integrations: $integration_count)"
    
    contact_group_id=$(create_contact_group_improved "$name" "$emails" "$sms_numbers" "$webhook_url" "$contact_type")
    
    if [[ -n "$contact_group_id" && "$contact_group_id" != "" ]]; then
        CONTACT_GROUP_MAP["$name"]="$contact_group_id"
        log_message "✅ Mapped contact '$name' to ID: $contact_group_id"
    else
        log_message "❌ Failed to get valid ID for contact '$name'"
    fi
    
done < <(jq -c '.results[]' contacts.json)

echo ""
echo "📊 Contact Groups Summary:"
echo "  ✅ Available: ${#CONTACT_GROUP_MAP[@]}"
echo "  ❌ Failed: ${#FAILED_CONTACT_GROUPS[@]}"
echo ""

# Show contact group mapping summary
log_message "Contact group mapping completed: ${#CONTACT_GROUP_MAP[@]} groups available"

# Only proceed with uptime checks if we have some contact groups  
if [[ ${#CONTACT_GROUP_MAP[@]} -gt 0 ]]; then
    echo "Step 2: Creating uptime checks..."
    echo "⚠️  Note: Will stop if plan limits are reached"
    echo ""
    
    log_message "Starting uptime check creation for $total_monitors monitors..."
    
    # Create temporary file with monitor data
    temp_file=$(mktemp)
    jq -c '.results[]' monitors.json > "$temp_file"
    total_lines=$(wc -l < "$temp_file")
    monitor_count=0
    
    for (( line_num=1; line_num<=total_lines; line_num++ )); do
        line=$(sed -n "${line_num}p" "$temp_file")
        monitor_count=$((monitor_count + 1))
        
        # Extract monitor data
        name=$(echo "$line" | jq -r '.name')
        url=$(echo "$line" | jq -r '.msp_address')
        interval_minutes=$(echo "$line" | jq -r '.msp_interval')
        contact_groups=$(echo "$line" | jq -r '.contact_groups[]' 2>/dev/null || echo "")
        expect_string=$(echo "$line" | jq -r '.msp_expect_string // empty')
        headers=$(echo "$line" | jq -r '.msp_headers // empty')
        
        # Convert minutes to seconds for our function
        if [[ -n "$interval_minutes" && "$interval_minutes" != "null" ]]; then
            interval_sec=$((interval_minutes * 60))
        else
            interval_sec="300"  # Default to 5 minutes
        fi
        
        log_message "[$monitor_count/$total_monitors] Processing monitor '$name'"
        log_message "  URL: $url, Interval: ${interval_minutes}min"
        
        # Log additional configuration if present
        if [[ -n "$expect_string" ]]; then
            log_message "  Expect String: $expect_string"
        fi
        if [[ -n "$headers" ]]; then
            log_message "  Custom Headers: $headers"
        fi
        
        # Skip if we're likely to hit limits (rough estimate)
        current_count=$(get_current_check_count)
        if [[ $current_count -ge 45 ]]; then
            log_message "⚠️  Approaching plan limits ($current_count checks), stopping uptime check creation"
            log_message "   Remaining monitors can be created manually or after upgrading plan"
            break
        fi
        
        # Convert interval to StatusCake check_rate
        check_rate=$(convert_interval_to_check_rate "$interval_sec")
        
        # Map contact names to contact group IDs
        contact_group_ids=""
        if [[ -n "$contact_groups" ]]; then
            contact_ids=()
            while IFS= read -r contact_name; do
                if [[ -n "${CONTACT_GROUP_MAP[$contact_name]:-}" ]]; then
                    contact_ids+=("${CONTACT_GROUP_MAP[$contact_name]}")
                    log_message "   Mapping contact '$contact_name' to ID: ${CONTACT_GROUP_MAP[$contact_name]}"
                fi
            done <<< "$contact_groups"
            contact_group_ids=$(IFS=','; echo "${contact_ids[*]}")
        fi
        
        log_message "   Creating with contact group IDs: $contact_group_ids"
        log_message "   Check rate: ${check_rate}s"
        
        # Prepare form data for uptime check
        form_data="name=$(printf '%s' "$name" | sed 's/ /%20/g' | sed 's/&/%26/g')"
        form_data+="&website_url=$(printf '%s' "$url" | sed 's/:/%3A/g' | sed 's/\//%2F/g' | sed 's/?/%3F/g' | sed 's/=/%3D/g')"
        form_data+="&test_type=HTTP"
        form_data+="&check_rate=$check_rate"
        form_data+="&regions[]=TORONTO"
        
        # Add find_string if expect_string is present
        if [[ -n "$expect_string" ]]; then
            encoded_string=$(printf '%s' "$expect_string" | sed 's/ /%20/g' | sed 's/"/%22/g' | sed 's/:/%3A/g' | sed 's/{/%7B/g' | sed 's/}/%7D/g' | sed 's/&/%26/g')
            form_data+="&find_string=$encoded_string"
            log_message "   Added find_string: $expect_string"
        fi
        
        # Add custom header if headers are present
        if [[ -n "$headers" ]]; then
            # StatusCake expects custom_header format: "Header-Name: Header-Value"
            encoded_header=$(printf '%s' "$headers" | sed 's/ /%20/g' | sed 's/:/%3A/g' | sed 's/&/%26/g')
            form_data+="&custom_header=$encoded_header"
            log_message "   Added custom_header: $headers"
        fi
        
        # Add contact groups if they exist
        if [[ -n "$contact_group_ids" ]]; then
            IFS=',' read -ra CG_ARRAY <<< "$contact_group_ids"
            for cg_id in "${CG_ARRAY[@]}"; do
                if [[ -n "$cg_id" ]]; then
                    form_data+="&contact_groups[]=$cg_id"
                fi
            done
        fi
        
        # Create the uptime check
        response=$(curl -sS -w "%{http_code}" \
            -X POST \
            -H "Authorization: Bearer $STATUSCAKE_API_TOKEN" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "$form_data" \
            "https://api.statuscake.com/v1/uptime" 2>/dev/null)
        
        http_code="${response: -3}"
        body="${response%???}"
        
        if [[ "$http_code" == "201" ]]; then
            check_id=$(echo "$body" | jq -r '.data.new_id')
            log_message "✅ Uptime check created with ID: $check_id"
            CREATED_UPTIME_CHECKS+=("$check_id:$name")
        elif [[ "$http_code" == "402" ]]; then
            log_message "❌ Plan limit reached for '$name' - stopping uptime check creation"
            FAILED_UPTIME_CHECKS+=("$name:Plan limits reached")
            break
        else
            log_message "❌ Failed to create uptime check '$name' (HTTP $http_code): $body"
            FAILED_UPTIME_CHECKS+=("$name:HTTP $http_code")
        fi
        
    done
    
    # Clean up temporary file
    rm -f "$temp_file"
    log_message "Completed uptime check creation process"
else
    echo "⚠️  Skipping uptime check creation - no contact groups available"
fi

# Generate summary
echo ""
echo "=== MIGRATION SUMMARY ==="
echo "📧 Contact Groups: ${#CONTACT_GROUP_MAP[@]} available, ${#FAILED_CONTACT_GROUPS[@]} failed"
echo "🔍 Uptime Checks: ${#CREATED_UPTIME_CHECKS[@]} created, ${#FAILED_UPTIME_CHECKS[@]} failed/skipped"
echo ""

if [[ ${#FAILED_CONTACT_GROUPS[@]} -gt 0 ]]; then
    echo "❌ Failed Contact Groups:"
    for failed in "${FAILED_CONTACT_GROUPS[@]}"; do
        name="${failed%%:*}"
        reason="${failed#*:}"
        echo "  - $name: $reason"
    done
    echo ""
fi

if [[ ${#PLACEHOLDER_CONTACTS[@]} -gt 0 ]]; then
    echo "🔧 Contact Groups Needing Manual Webhook Setup:"
    for contact_name in "${!PLACEHOLDER_CONTACTS[@]}"; do
        echo "  - $contact_name: ${PLACEHOLDER_CONTACTS[$contact_name]}"
    done
    echo ""
fi

echo "📝 Next Steps:"
echo "1. Check StatusCake dashboard for created resources"
echo "2. Set up webhook URLs for contacts that need them"
 