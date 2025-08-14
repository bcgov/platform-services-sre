# Uptime.com to StatusCake Migration Scripts

This directory contains two scripts that work together to migrate your monitoring setup from uptime.com to StatusCake.

## 📋 Overview

The migration process consists of two steps:
1. **Export data from uptime.com** using `migration-from-uptime.sh`
2. **Import data into StatusCake** using `migrate-to-statuscake-improved.sh`

## 🚀 Quick Start

### Step 1: Export from Uptime.com

```bash
# Set your uptime.com API token
export UPTIME_API_TOKEN="your_uptime_api_token_here"

# Run the export script
./migration-from-uptime.sh
```

### Step 2: Import to StatusCake

```bash
# Set your StatusCake API token (for the target workspace)
export STATUSCAKE_API_TOKEN="your_statuscake_api_token_here"

# Run the import script
./migrate-to-statuscake-improved.sh
```

## 📖 Detailed Documentation

### Script 1: `migration-from-uptime.sh`

**Purpose**: Exports all monitoring data from your uptime.com account.

#### Prerequisites

- **Uptime.com API Token**: Get this from your uptime.com account settings
- **jq**: JSON processor (install with `brew install jq` on macOS)
- **curl**: For API requests (usually pre-installed)

#### What it exports

- **Contacts**: All contact groups with email and SMS settings
- **Integrations**: Webhook and notification integrations
- **Monitors**: All uptime checks with their configurations
- **Summary Report**: Human-readable overview of exported data

#### Configuration

The script is configured to export from the **"Platform Services"** subaccount. To change this:

```bash
# Edit the script and modify this line:
TARGET_SUBACCOUNT="Your Subaccount Name"

# Examples (use the exact name from the dropdown on the left):
TARGET_SUBACCOUNT="Developer Experience Team"
TARGET_SUBACCOUNT="Digital PIA Team"
TARGET_SUBACCOUNT="Platform Services"
```

**Note**: Use the exact subaccount name as it appears in the dropdown on the left side of uptime.com. Spaces are allowed. For more details, see the [Subaccounts section](https://app.uptime.com/api/tokens) in the uptime.com API documentation.

#### Output Files

- `contacts.json` - Contact groups data
- `integrations.json` - Integration configurations  
- `monitors.json` - Monitor/check configurations
- `export_summary.txt` - Human-readable summary

#### Usage Example

```bash
# Set your token
export UPTIME_API_TOKEN="uptk_1234567890abcdef"

# Run export
./migration-from-uptime.sh

# Output:
# === UPTIME.COM DATA EXPORT ===
# Step 1: Finding subaccount...
# Using subaccount ID: 12345
# 
# Step 2: Fetching contacts...
# Contacts exported to contacts.json
# Contact count: 9
# ...
```

---

### Script 2: `migrate-to-statuscake-improved.sh`

**Purpose**: Creates equivalent monitoring resources in StatusCake using the exported data.

#### Prerequisites

- **StatusCake API Token**: 
  1. Login to StatusCake: https://app.statuscake.com/Login/
  2. Navigate to: https://app.statuscake.com/User.php
  3. Scroll to bottom of page → **API Keys** section
  4. Generate/copy your API token
- **Exported JSON files**: Must have run `migration-from-uptime.sh` first
- **jq**: JSON processor
- **curl**: For API requests

#### What it creates

- **Contact Groups**: Migrates all contact groups with email/SMS settings
- **Uptime Checks**: Creates equivalent monitoring checks
- **Regional Monitoring**: All checks monitor from **Toronto, Canada**
- **Contact Mapping**: Links checks to appropriate contact groups

#### Key Features

- ✅ **Automatic contact group mapping**: Reuses existing groups, creates missing ones
- ✅ **Plan limit handling**: Stops gracefully when StatusCake limits are reached
- ✅ **Error handling**: Retries failed API calls, provides detailed logging
- ✅ **Webhook placeholder**: Marks integration-based contacts for manual setup
- ✅ **Regional monitoring**: All checks use Toronto region for Canadian compliance

#### Configuration

The script automatically configures:
- **Monitoring Region**: Toronto, Canada (`TORONTO`)
- **Retry Logic**: 3 attempts with 2-second delays
- **Plan Limit**: Stops at ~45 checks to avoid hitting limits

#### Output

- `statuscake_migration_improved.log` - Detailed migration log
- `migration_summary.txt` - Final summary report
- Console output with real-time progress

#### Usage Example

```bash
# Set your StatusCake token (for target workspace)
export STATUSCAKE_API_TOKEN="Bearer_your_token_here"

# Run migration
./migrate-to-statuscake-improved.sh

# Expected Output:
# === STATUSCAKE MIGRATION ===
# Migrating uptime.com data to StatusCake
# 
# 🔍 Checking current StatusCake status...
# Current uptime checks: 25
# Monitors to migrate: 25
# 
# Step 1: Creating contact groups...
# ✅ Mapped contact 'platform-services-admins' to ID: 344914
# ...
```


### Manual Steps Required

After migration, you'll need to:

  1. **Set up webhooks**: Contact groups with integrations need manual webhook configuration. See [RocketChat Integration Guide](Rocketchat/alerts_with_RC.md) for detailed setup instructions 
2. **Review settings**: Verify check intervals and contact assignments
3. **Test alerts**: Confirm notifications work as expected


### Log Files

- `statuscake_migration_improved.log`: Detailed migration log
- `export_summary.txt`: Summary of exported uptime.com data

### Note
1. Check the log files for specific error messages
2. Verify your API tokens are correct and for the right workspace
3. Ensure all prerequisite files exist (contacts.json, monitors.json, etc.)
4. Contact StatusCake support if you encounter API-specific issues

