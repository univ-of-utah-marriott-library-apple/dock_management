#!/bin/bash
#
# Dock Setup Script - dockutil 3 Template
#
# Revised: 2026.08.06
# Version: 2.4.0
#
# This script is designed to set up a managed Dock with dockutil 3. By default
# it targets the active GUI user, but it can also target all homes, a specific
# home, a specific Dock plist, or a default user template.
#
# Key Features:
#
#   - Enhanced error handling and validation
#   - Better logging with different severity levels
#   - Improved process detection and waiting
#   - Path validation for applications and folders
#   - Configuration validation with missing item filtering
#   - Optional once-per-user marker file
#   - Performance optimizations with dockutil 3 multi-action batching
#
# How to customize:
#
#   1. Edit the "Site configuration" values below.
#   2. Edit the ADD_* arrays for your preferred Dock items.
#   3. Leave RUN_ONCE_PER_USER=true for first-login current-user workflows.
#   4. Deploy with Outset, Jamf, Munki, Mosyle, or another management tool.
#
# Notes for community use:
#
#   - Current-user workflows run dockutil via launchctl asuser by default.
#   - Current-user workflows wait for Dock and Finder before touching com.apple.dock.plist.
#   - All dockutil add/remove actions are batched with --no-restart.
#   - Current-user workflows restart Dock once unless RESTART_DOCK=false.
#   - This intentionally defaults to the active GUI user; allhomes/plist/home targets are optional.
#
# Version History:
#
#   2.4.0 - Added generic MacAdmins options for targets, removals, positions, folders, and spacers
#   2.3.1 - Added dockutil auto-detection and dockutil 3 multi-action batching
#   2.3.0 - Made template community-friendly with site config, item filtering, and run-once marker
#   2.2.1 - Changed to detect first GUI login on system (not user) for better timeout handling
#   2.2.2 - Removed first GUI login detection - dock stabilization checks are sufficient
#   2.2.3 - Optimized dock detection timings for faster managed dock updates
#   2.2.4 - Fixed floating point arithmetic issues and LOG_DIR initialization
#   2.2.5 - Fixed readonly variable conflicts for LOG_DIR and LOG_FILE
#   2.2.0 - Added first login detection with adaptive timeout behavior
#   2.1.9 - Set 60s timeout for dock stabilization, exit gracefully to preserve OS default dock
#   2.1.8 - Enhanced dock stabilization checks to handle OS default item setup on first login
#   2.1.7 - Fixed function name typo and added indirect function call annotations
#   2.1.6 - Added more robust URL validation and enhanced error messaging for web locations
#   2.1.5 - Fixed duplicate timing functions and improved version history clarity
#   2.1.4 - Added dock content verification and retry mechanism
#   2.1.3 - Fixed dockutil command syntax and improved error handling
#   2.1.2 - Added dock verification and stability checks
#   2.1.1 - Fixed log directory handling and added dock restart timeout
#   2.1.0 - Added user template dock completion monitoring
#   2.0.9 - Added dock settings stabilization check before modifications
#   2.0.8 - Added timing improvements for more reliable dock modifications
#   2.0.7 - Changed logging to user's Library/Logs directory
#   2.0.6 - Fixed log directory permissions and prevented multiple Dock restarts
#   2.0.3 - Enhanced dock clearing with proper flags for removing all default items
#   2.0.2 - Added handling for pre-existing Dock items
#   2.0.1 - Improved error handling and app validation
#   2.0.0 - Initial version with enhanced validation and logging
#
# Copyright (c) 2026 University of Utah, Marriott Library IT. 
# All Rights Reserved.
#
# Permission to use, copy, modify, and distribute this software and
# its documentation for any purpose and without fee is hereby granted,
# provided that the above copyright notice appears in all copies and
# that both that copyright notice and this permission notice appear
# in supporting documentation, and that the name of The University
# of Utah not be used in advertising or publicity pertaining to
# distribution of the software without specific, written prior
# permission. This software is supplied as is without expressed or
# implied warranties of any kind.

##################################
# Configuration & Global Variables
##################################

# Simple timing for overall execution
format_duration()
{
    local seconds=$1
    printf "%dm:%02ds" $((seconds/60)) $((seconds%60))
}

# Script configuration
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="2.4.0"
readonly MIN_DOCKUTIL_VERSION="3.0.0"  # Minimum required dockutil version

##################################
# Site configuration - edit here
##################################

readonly ORG_NAME="Example Organization"
readonly LOG_BASENAME="dock_setup"

# Target modes:
#   current_user          Active GUI user's Dock. Recommended for Outset/Jamf/Munki login workflows.
#   current_user_home     Active GUI user's home directory path is passed to dockutil explicitly.
#   allhomes              Adds --allhomes. Useful only when you truly want every local home.
#   home                  Passes DOCK_TARGET_HOME to dockutil.
#   plist                 Passes DOCK_TARGET_PLIST to dockutil.
#   default_user_template Passes DEFAULT_USER_TEMPLATE_PATH to dockutil.
readonly DOCK_TARGET_MODE="current_user"
readonly DOCK_TARGET_HOME=""
readonly DOCK_TARGET_PLIST=""
readonly DOCK_HOMES_ROOT="/Users"
readonly DEFAULT_USER_TEMPLATE_PATH="/System/Library/User Template/English.lproj"

# Run dockutil through launchctl asuser for the active GUI user. This must be
# false for allhomes/home/plist/default_user_template target modes.
readonly RUN_DOCKUTIL_AS_USER=true

# Set true for first-login workflows where each user should receive the managed
# Dock once. Set false if every run should rebuild the Dock.
readonly RUN_ONCE_PER_USER=true
readonly MARKER_FILE_BASENAME="com.example.docksetup.done"

# Set to true if missing apps/folders should fail the script instead of being skipped.
readonly REQUIRE_ALL_ITEMS=false

# Set false if you are only adding/removing a few items and do not want to clear the Dock first.
readonly CLEAR_DOCK_FIRST=true

# Verification is helpful for current-user workflows. Non-GUI target modes skip
# verification because --list is only meaningful for a specific active user.
readonly VERIFY_DOCK_CONTENTS=true

# Restart Dock once at the end for GUI-user workflows. Non-GUI target modes skip
# restart because there is no active user's Dock process to restart.
readonly RESTART_DOCK=true

# Paths outside this regex are skipped. Add site-specific locations as needed.
readonly ALLOWED_PATH_REGEX='^(/Applications|/System|/Users/[^/]+/Downloads|/Users/[^/]+/Documents|/Users/[^/]+/Desktop|/Network/Applications|/System/Volumes/Data/Applications|/System/Cryptexes/App/System/Applications|/System/Library/CoreServices)'

# Logging configuration
set_log_paths()
{
    # Only set paths if they haven't been set already
    if [[ -z "$LOG_DIR" ]]; then
        # Use a temporary variable to avoid readonly conflicts
        local temp_log_dir
        # Set initial log directory path
        if [[ -n "$LOGGED_IN_USER" && "$LOGGED_IN_USER" != "root" ]]; then
            temp_log_dir="/Users/$LOGGED_IN_USER/Library/Logs/$LOG_BASENAME"
        else
            temp_log_dir="/tmp/$LOG_BASENAME"
        fi
        
        # Only assign if we successfully determined a path
        if [[ -n "$temp_log_dir" ]]; then
            LOG_DIR="$temp_log_dir"
            LOG_FILE="$LOG_DIR/$LOG_BASENAME.log"
        fi
    fi
    
    # Actual directory and file creation is handled by ensure_log_directory
}

# Paths
DOCKUTIL_PATH="${DOCKUTIL_PATH:-}"
readonly -a DOCKUTIL_CANDIDATE_PATHS=(
    "/usr/local/bin/dockutil"
    "/opt/homebrew/bin/dockutil"
    "/usr/bin/dockutil"
)
readonly KILLALL_PATH="/usr/bin/killall"
readonly SCUTIL_PATH="/usr/sbin/scutil"
readonly PGREP_PATH="/usr/bin/pgrep"

# Timeouts and intervals - optimized for speed
readonly PROCESS_WAIT_TIMEOUT=30     # seconds
readonly USER_WAIT_TIMEOUT=180       # 3 minutes
readonly DOCK_RESTART_DELAY=1        # seconds
readonly PROCESS_CHECK_INTERVAL=1    # seconds (changed from 0.5 to avoid floating point arithmetic)

# ANSI color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Dock items - customize these arrays for your environment.
#
# Paths can use $HOME or ~ only for current_user, current_user_home, and home modes.
# Simple formats:
#   ADD_APPS_TO_DOCK: "/Applications/App.app"
#   ADD_FOLDERS_TO_DOCK: "$HOME/Downloads"
#   ADD_WEBLOCATIONS_TO_DOCK: "https://example.org|Label"
#
# Advanced optional formats:
#   Apps:    "path|section|position"
#   Folders: "path|view|display|sort|position"
#   URLs:    "url|label|section|position"
#   Spacers: "section|position"
#
# section: apps or others
# position: end, beginning, middle, index number, after:Label, before:Label
#
# Remove items before adding. Use "all" to rebuild the Dock from scratch, or
# labels/bundle IDs/spacer-tiles for targeted cleanup.
declare -a REMOVE_ITEMS_FROM_DOCK=(
    "all"
)

declare -a ADD_APPS_TO_DOCK=(
    "/Applications/Google Chrome.app"
    "/Applications/Firefox.app"
    "/System/Applications/Safari.app"
    "/System/Applications/System Settings.app"
)

declare -a ADD_FOLDERS_TO_DOCK=(
    "\$HOME/Downloads"
)

declare -a ADD_WEBLOCATIONS_TO_DOCK=(
    "https://support.example.org|Support"
)

declare -a ADD_ADDITIONAL_APPS_TO_DOCK=(
    "/Applications/Utilities/Self Service.app"
)

declare -a ADD_SPACERS_TO_DOCK=(
)

# These arrays are populated during validation so missing optional items do not
# cause verification to fail after being skipped.
declare -a VALID_APPS_TO_DOCK=()
declare -a VALID_FOLDERS_TO_DOCK=()
declare -a VALID_WEBLOCATIONS_TO_DOCK=()
declare -a VALID_ADDITIONAL_APPS_TO_DOCK=()
declare -a VALID_SPACERS_TO_DOCK=()
declare -a DOCKUTIL_ACTIONS=()

# Global variables
LOGGED_IN_USER=""
USER_UID=""

# Timing variables
SCRIPT_START_TIME=$(date +%s)

##################################
# Logging Functions
##################################

ensure_log_directory()
{
    # First make sure we can determine where to create the log directory
    if [[ -z "$LOG_DIR" ]]; then
        echo "ERROR: LOG_DIR is not set" >&2
        return 1
    fi

    # If directory doesn't exist, create it with proper permissions
    if [[ ! -d "$LOG_DIR" ]]; then
        if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
            echo "ERROR: Failed to create log directory: $LOG_DIR" >&2
            return 1
        fi

        # Set proper permissions
        if ! chmod 755 "$LOG_DIR" 2>/dev/null; then
            echo "ERROR: Failed to set permissions on log directory" >&2
            return 1
        fi

        # Set ownership if running as root and we have a user.
        if [[ $EUID -eq 0 && -n "$LOGGED_IN_USER" ]]; then
            if ! chown "$LOGGED_IN_USER:staff" "$LOG_DIR" 2>/dev/null; then
                echo "ERROR: Failed to set ownership of log directory" >&2
                return 1
            fi
        fi
    fi
    
    # Final verification that directory exists and is writable
    if [[ ! -d "$LOG_DIR" ]]; then
        echo "ERROR: Log directory does not exist after creation attempt: $LOG_DIR" >&2
        return 1
    fi

    if [[ ! -w "$LOG_DIR" ]]; then
        echo "ERROR: Log directory is not writable: $LOG_DIR" >&2
        return 1
    fi
    
    return 0
}

log_message()
{
    local level="$1"
    local message="$2"
    local timestamp
    timestamp="$(date +%Y.%m.%d_%T)"
    
    # Ensure log directory exists
    if ! ensure_log_directory; then
        echo "ERROR: Unable to write log entry: [$timestamp - $level] $message" >&2
        return 1
    fi
    
    # Format the log message for file (without colors)
    local log_entry="[$timestamp - $level] $message"
    echo "$log_entry" >> "$LOG_FILE"
    
    # Format the log message for console (with colors)
    case "$level" in
        "INFO")  echo -e "${BLUE}[$timestamp - INFO]${NC}  $message" ;;
        "SUCCESS") echo -e "${GREEN}[$timestamp - SUCCESS]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp - WARN]${NC}  $message" ;;
        "ERROR") echo -e "${RED}[$timestamp - ERROR]${NC} $message" ;;
        "CMD")   echo -e "[$timestamp - CMD]   $message" ;;
        "TIMING") echo -e "${BLUE}[$timestamp - TIMING]${NC} $message" ;;
        *) echo -e "[$timestamp - $level] $message" ;;
    esac
}

log_separator()
{
    echo "------------------------------------------------------------------------"
}

resolve_user_path()
{
    local path="$1"
    local user_home=""

    if [[ -n "$LOGGED_IN_USER" ]]; then
        user_home="/Users/$LOGGED_IN_USER"
    elif [[ "$DOCK_TARGET_MODE" == "home" && -n "$DOCK_TARGET_HOME" ]]; then
        user_home="${DOCK_TARGET_HOME%/}"
    fi

    case "$path" in
        "~")
            if [[ -n "$user_home" ]]; then
                printf "%s" "$user_home"
            else
                printf "%s" "$path"
            fi
            ;;
        \~/*)
            if [[ -n "$user_home" ]]; then
                printf "%s/%s" "$user_home" "${path#\~/}"
            else
                printf "%s" "$path"
            fi
            ;;
        "\$HOME")
            if [[ -n "$user_home" ]]; then
                printf "%s" "$user_home"
            else
                printf "%s" "$path"
            fi
            ;;
        "\$HOME/"*)
            if [[ -n "$user_home" ]]; then
                printf "%s/%s" "$user_home" "${path#\$HOME/}"
            else
                printf "%s" "$path"
            fi
            ;;
        *)
            printf "%s" "$path"
            ;;
    esac
}

field_at()
{
    local record="$1"
    local index="$2"
    local IFS='|'
    local -a fields

    read -r -a fields <<< "$record"
    printf "%s" "${fields[$index]:-}"
}

append_position_args()
{
    local position="${1:-end}"

    case "$position" in
        "")
            DOCKUTIL_ACTIONS+=("--position" "end")
            ;;
        after:*)
            DOCKUTIL_ACTIONS+=("--after" "${position#after:}")
            ;;
        before:*)
            DOCKUTIL_ACTIONS+=("--before" "${position#before:}")
            ;;
        *)
            DOCKUTIL_ACTIONS+=("--position" "$position")
            ;;
    esac
}

append_dock_target_args()
{
    case "$DOCK_TARGET_MODE" in
        current_user)
            return 0
            ;;
        current_user_home)
            DOCKUTIL_ACTIONS+=("/Users/$LOGGED_IN_USER")
            ;;
        allhomes)
            if [[ -n "$DOCK_HOMES_ROOT" && "$DOCK_HOMES_ROOT" != "/Users" ]]; then
                DOCKUTIL_ACTIONS+=("--homeloc" "$DOCK_HOMES_ROOT")
            fi
            DOCKUTIL_ACTIONS+=("--allhomes")
            ;;
        home)
            if [[ -z "$DOCK_TARGET_HOME" ]]; then
                log_message "ERROR" "DOCK_TARGET_MODE=home requires DOCK_TARGET_HOME"
                return 1
            fi
            DOCKUTIL_ACTIONS+=("$(resolve_user_path "$DOCK_TARGET_HOME")")
            ;;
        plist)
            if [[ -z "$DOCK_TARGET_PLIST" ]]; then
                log_message "ERROR" "DOCK_TARGET_MODE=plist requires DOCK_TARGET_PLIST"
                return 1
            fi
            DOCKUTIL_ACTIONS+=("$(resolve_user_path "$DOCK_TARGET_PLIST")")
            ;;
        default_user_template)
            DOCKUTIL_ACTIONS+=("$DEFAULT_USER_TEMPLATE_PATH")
            ;;
        *)
            log_message "ERROR" "Unknown DOCK_TARGET_MODE: $DOCK_TARGET_MODE"
            return 1
            ;;
    esac
}

##################################
# Utility Functions
##################################

# Function to get the currently logged-in user
get_current_user()
{
    echo "show State:/Users/ConsoleUser" | "$SCUTIL_PATH" 2>/dev/null | awk '/Name :/ && ! /loginwindow/ { print $3 }'
}

# Function to check if a process is running
is_process_running()
{
    local process_name="$1"
    "$PGREP_PATH" -xq "$process_name" 2>/dev/null
}

# Function to validate URL dock items.
validate_url()
{
    local url="$1"

    [[ "$url" =~ ^https?://[^[:space:]]+$ ]]
}

uses_home_placeholder()
{
    local value="$1"

    [[ "$value" == \~ || "$value" == \~/* || "$value" == "\$HOME" || "$value" == "\$HOME/"* ]]
}

# Function to validate that a path exists and is accessible
validate_path()
{
    if [[ $# -lt 2 ]]; then
        log_message "ERROR" "validate_path requires path and type arguments"
        return 1
    fi
    
    local path
    path="${1%/}"  # Remove trailing slash if present
    local path_type="$2"
    local resolved_path
    
    # Check for empty path
    if [[ -z "$path" ]]; then
        log_message "ERROR" "Empty path provided"
        return 1
    fi
    
    # Check for valid path type
    if [[ ! "$path_type" =~ ^(app|folder|file)$ ]]; then
        log_message "ERROR" "Invalid path type: $path_type. Must be 'app', 'folder', or 'file'"
        return 1
    fi
    
    path="$(resolve_user_path "$path")"
    
    # Resolve any symbolic links with macOS-compatible tooling.
    if [[ -e "$path" ]]; then
        local path_dir path_base resolved_dir
        path_dir="$(dirname "$path")"
        path_base="$(basename "$path")"
        if resolved_dir=$(cd "$path_dir" 2>/dev/null && pwd -P); then
            resolved_path="$resolved_dir/$path_base"
        else
            resolved_path="$path"
        fi
    else
        log_message "INFO" "Could not resolve symbolic link for $path, using original path"
        resolved_path="$path"  # Fall back to original path if readlink fails
    fi

    if [[ "$resolved_path" != "$path" ]]; then
        # Enhanced security checks for symlinks and path traversal
        if [[ "$resolved_path" =~ \.\./ ]] || 
           [[ "$resolved_path" =~ //+ ]] || 
           [[ "$resolved_path" =~ ^[[:space:]]+ ]] || 
           [[ "$resolved_path" =~ [[:space:]]+$ ]] || 
           [[ "$resolved_path" =~ [\|\&\;\<\>\$\`\\] ]]; then
            log_message "ERROR" "Security check failed for path: $path -> $resolved_path"
            log_message "ERROR" "Path contains invalid characters or potential security risks"
            return 1
        fi
        log_message "INFO" "Path $path resolves to $resolved_path"
    fi
    
    # Check if path exists within allowed dock-related directories
    if [[ ! "$resolved_path" =~ $ALLOWED_PATH_REGEX ]]; then
        log_message "WARN" "Path $path resolves outside of allowed dock directories"
        log_message "INFO" "Attempted path: $resolved_path"
        return 1
    fi
    
    case "$path_type" in
        "app")
            if [[ -d "$path" && "$path" == *.app ]]; then
                return 0
            else
                log_message "WARN" "Application not found or invalid: $path"
                return 1
            fi
            ;;
        "folder")
            if [[ -d "$path" ]]; then
                return 0
            else
                log_message "WARN" "Folder not found: $path"
                return 1
            fi
            ;;
        "file")
            if [[ -f "$path" ]]; then
                return 0
            else
                log_message "WARN" "File not found: $path"
                return 1
            fi
            ;;
        *)
            if [[ -e "$path" ]]; then
                return 0
            else
                log_message "WARN" "Path not found: $path"
                return 1
            fi
            ;;
    esac
}

# Function to ensure Downloads folder exists and has correct permissions
ensure_downloads_folder()
{
    local downloads_path="/Users/$LOGGED_IN_USER/Downloads"
    
    if [[ ! -d "$downloads_path" ]]; then
        log_message "INFO" "Creating Downloads folder for user: $LOGGED_IN_USER"
        if ! mkdir -p "$downloads_path"; then
            log_message "ERROR" "Failed to create Downloads folder"
            return 1
        fi
    fi
    
    # Always ensure correct permissions, even if folder exists
    if [[ $EUID -eq 0 ]]; then
        if ! chown "$LOGGED_IN_USER:staff" "$downloads_path" 2>/dev/null; then
            log_message "ERROR" "Failed to set ownership on Downloads folder"
            return 1
        fi
    fi
    
    if ! chmod 755 "$downloads_path" 2>/dev/null; then
        log_message "ERROR" "Failed to set permissions on Downloads folder"
        return 1
    fi
    
    # Verify permissions
    if [[ ! -w "$downloads_path" ]]; then
        log_message "ERROR" "Downloads folder is not writable: $downloads_path"
        return 1
    fi
}

get_marker_file()
{
    printf "/Users/%s/Library/Preferences/%s" "$LOGGED_IN_USER" "$MARKER_FILE_BASENAME"
}

dock_already_configured()
{
    [[ "$RUN_ONCE_PER_USER" == true ]] && target_requires_gui_user && [[ -f "$(get_marker_file)" ]]
}

write_completion_marker()
{
    if [[ "$RUN_ONCE_PER_USER" != true ]] || ! target_requires_gui_user; then
        return 0
    fi

    local marker_file
    marker_file="$(get_marker_file)"

    if ! touch "$marker_file"; then
        log_message "ERROR" "Failed to write completion marker: $marker_file"
        return 1
    fi

    if [[ $EUID -eq 0 ]]; then
        chown "$LOGGED_IN_USER:staff" "$marker_file" 2>/dev/null || true
    fi
    chmod 644 "$marker_file" 2>/dev/null || true
    log_message "SUCCESS" "Wrote completion marker: $marker_file"
}

downloads_folder_configured()
{
    local folder_record folder_path expanded_path

    for folder_record in "${VALID_FOLDERS_TO_DOCK[@]}"; do
        folder_path="$(field_at "$folder_record" 0)"
        expanded_path="$(resolve_user_path "$folder_path")"
        if [[ "$expanded_path" == "/Users/$LOGGED_IN_USER/Downloads" ]]; then
            return 0
        fi
    done

    return 1
}

customize_dock_items_for_user()
{
    # Optional site hook. Example:
    #
    # if [[ "$LOGGED_IN_USER" == "localadmin" ]]; then
    #     ADD_APPS_TO_DOCK=("/System/Applications/Utilities/Terminal.app")
    #     ADD_FOLDERS_TO_DOCK=()
    #     ADD_WEBLOCATIONS_TO_DOCK=()
    # fi
    return 0
}

# Function to run command with retries and exponential backoff.
run_with_retry()
{
    local max_attempts=3
    local attempt=1
    local sleep_time=1
    local last_error=""
    local output
    
    while ((attempt <= max_attempts)); do
        if output="$("$@" 2>&1)"; then
            [[ -n "$output" ]] && log_message "INFO" "Command output: ${output}"
            return 0
        else
            last_error="${output}"
        fi
        log_message "WARN" "Command failed (attempt $attempt/$max_attempts), retrying in ${sleep_time}s..."
        [[ -n "$last_error" ]] && log_message "WARN" "Error output: $last_error"
        sleep "$sleep_time"
        ((attempt++))
        ((sleep_time *= 2))
    done
    
    # Log final error if we have one
    [[ -n "$last_error" ]] && log_message "ERROR" "Final error output: $last_error"
    return 1
}

# Function to run command as user with better error handling
run_as_user()
{
    if [[ -z "$LOGGED_IN_USER" || "$LOGGED_IN_USER" == "loginwindow" ]]; then
        log_message "ERROR" "No valid user to run command as"
        return 1
    fi
    
    if [[ -z "$USER_UID" ]]; then
        log_message "ERROR" "User UID not available"
        return 1
    fi
    
    # Log the command with proper escaping
    local cmd_str
    printf -v cmd_str '%q ' "$@"
    log_message "CMD" "launchctl asuser $USER_UID $cmd_str" >&2
    
    local output
    output=$(launchctl asuser "$USER_UID" env LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 "$@" 2>&1)
    local error_code=$?
    if [[ $error_code -ne 0 ]]; then
        log_message "ERROR" "Failed to execute command as user $LOGGED_IN_USER (exit code: $error_code)" >&2
        [[ -n "$output" ]] && log_message "ERROR" "Command output: $output" >&2
        return "$error_code"
    fi

    [[ -n "$output" ]] && printf "%s\n" "$output"
    
    return 0
}

run_direct()
{
    local cmd_str output error_code

    printf -v cmd_str '%q ' "$@"
    log_message "CMD" "$cmd_str" >&2

    output=$("$@" 2>&1)
    error_code=$?
    if [[ $error_code -ne 0 ]]; then
        log_message "ERROR" "Command failed (exit code: $error_code)" >&2
        [[ -n "$output" ]] && log_message "ERROR" "Command output: $output" >&2
        return "$error_code"
    fi

    [[ -n "$output" ]] && printf "%s\n" "$output"
    return 0
}

run_dockutil()
{
    if [[ "$RUN_DOCKUTIL_AS_USER" == true ]]; then
        run_as_user "$DOCKUTIL_PATH" "$@"
    else
        run_direct "$DOCKUTIL_PATH" "$@"
    fi
}

find_dockutil()
{
    if [[ -n "$DOCKUTIL_PATH" && -x "$DOCKUTIL_PATH" ]]; then
        return 0
    fi

    local candidate
    for candidate in "${DOCKUTIL_CANDIDATE_PATHS[@]}"; do
        if [[ -x "$candidate" ]]; then
            DOCKUTIL_PATH="$candidate"
            return 0
        fi
    done

    return 1
}

##################################
# Validation Functions
##################################

# Enhanced dockutil check with version verification
check_dockutil()
{
    log_message "INFO" "Checking dockutil availability..."
    
    if ! find_dockutil; then
        log_message "ERROR" "dockutil not found or not executable. Checked: ${DOCKUTIL_CANDIDATE_PATHS[*]}"
        return 1
    fi
    
    # Check dockutil version and functionality
    local version_output
    if ! version_output=$("$DOCKUTIL_PATH" --version 2>&1); then
        log_message "ERROR" "Failed to get dockutil version"
        return 1
    fi
    
    # Version comparison
    if ! [[ "$version_output" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        log_message "ERROR" "Could not parse dockutil version: $version_output"
        return 1
    fi
    
    local current_version="${BASH_REMATCH[1]}"
    if ! version_at_least "$current_version" "$MIN_DOCKUTIL_VERSION"; then
        log_message "ERROR" "dockutil version $current_version is below minimum required version $MIN_DOCKUTIL_VERSION"
        return 1
    fi
    
    log_message "SUCCESS" "dockutil $current_version is available at $DOCKUTIL_PATH"
    return 0
}

version_at_least()
{
    local current="$1"
    local minimum="$2"
    local IFS=.
    local -a current_parts minimum_parts
    local i current_part minimum_part

    read -r -a current_parts <<< "$current"
    read -r -a minimum_parts <<< "$minimum"

    for i in 0 1 2; do
        current_part="${current_parts[$i]:-0}"
        minimum_part="${minimum_parts[$i]:-0}"

        if ((10#$current_part > 10#$minimum_part)); then
            return 0
        elif ((10#$current_part < 10#$minimum_part)); then
            return 1
        fi
    done

    return 0
}

# Current-user process checking with timeout and dock setup completion monitoring
check_required_processes()
{
    log_message "INFO" "Waiting for required processes and initial dock setup..."
    
    local elapsed=0
    local dock_plist
    if [[ -n "$LOGGED_IN_USER" && "$LOGGED_IN_USER" != "root" ]]; then
        dock_plist="/Users/$LOGGED_IN_USER/Library/Preferences/com.apple.dock.plist"
    else
        dock_plist="$HOME/Library/Preferences/com.apple.dock.plist"
    fi
    local initial_dock_hash=""
    local current_dock_hash=""
    local stabilization_count=0
    local required_stable_iterations=1
    
    local dock_timeout=15
    
    log_message "INFO" "Using fast timeout of ${dock_timeout}s for dock stabilization"
    
    # First wait for Dock and Finder to be running with faster checks
    while ! is_process_running "Dock" || ! is_process_running "Finder"; do
        if [[ $elapsed -ge $PROCESS_WAIT_TIMEOUT ]]; then
            log_message "ERROR" "Timeout waiting for required processes (${PROCESS_WAIT_TIMEOUT}s)"
            return 1
        fi
        
        local missing_processes=()
        is_process_running "Dock" || missing_processes+=("Dock")
        is_process_running "Finder" || missing_processes+=("Finder")
        
        log_message "INFO" "Waiting for processes: ${missing_processes[*]} (${elapsed}s elapsed)"
        sleep $PROCESS_CHECK_INTERVAL
        elapsed=$((elapsed + PROCESS_CHECK_INTERVAL))
    done
    
    log_message "INFO" "Required processes are running, waiting for initial dock setup to complete..."
    
    # Wait for dock preferences file to be created and initial setup to complete
    elapsed=0
    while [[ $elapsed -lt $dock_timeout ]]; do
        if [[ ! -f "$dock_plist" ]]; then
            log_message "INFO" "Waiting for dock preferences file to be created..."
            sleep $PROCESS_CHECK_INTERVAL
            ((elapsed += PROCESS_CHECK_INTERVAL))
            continue
        fi
        
        # Check if dock plist is readable and valid
        if ! plutil -lint "$dock_plist" >/dev/null 2>&1; then
        if ! defaults read "$dock_plist" >/dev/null 2>&1; then
            log_message "INFO" "Waiting for dock preferences to be accessible..."
            sleep $PROCESS_CHECK_INTERVAL
            ((elapsed += PROCESS_CHECK_INTERVAL))
                continue
            fi
        fi
        
        # Check if dock has default items (indicates OS is still setting up)
        local dock_items_count=0
        if dock_items_count=$(defaults read "$dock_plist" persistent-apps 2>/dev/null | grep -c "file-label" 2>/dev/null); then
            # If dock is empty, OS might still be setting up - but don't wait too long
            if [[ $dock_items_count -eq 0 ]]; then
                log_message "INFO" "Dock is empty, waiting briefly for OS setup..."
                sleep $PROCESS_CHECK_INTERVAL
                ((elapsed += PROCESS_CHECK_INTERVAL))
                continue
            fi
        fi
        
        # Check for dock stability using hash comparison - faster method
        local new_hash=""
        if new_hash=$(defaults read "$dock_plist" 2>/dev/null | shasum -a 256 2>/dev/null); then
            # Use defaults read first as it's faster than plist conversion
            current_dock_hash="$new_hash"
        elif new_hash=$(plutil -convert xml1 -o - "$dock_plist" 2>/dev/null | shasum -a 256 2>/dev/null); then
            # Fall back to plist conversion if defaults read fails
            current_dock_hash="$new_hash"
        else
            log_message "INFO" "Unable to get dock settings hash, retrying..."
            sleep $PROCESS_CHECK_INTERVAL
            ((elapsed += PROCESS_CHECK_INTERVAL))
            continue
        fi
        
        if [[ -n "$new_hash" ]]; then
            if [[ -n "$initial_dock_hash" && "$current_dock_hash" == "$initial_dock_hash" ]]; then
                ((stabilization_count++))
                log_message "INFO" "Dock stable for ${stabilization_count}/${required_stable_iterations} checks"
                
                if [[ $stabilization_count -ge $required_stable_iterations ]]; then
                    log_message "SUCCESS" "Dock has been stable for ${required_stable_iterations} check(s) - ready for modifications"
                    return 0
                fi
            else
                initial_dock_hash="$current_dock_hash"
                stabilization_count=0
                log_message "INFO" "Dock configuration changed, resetting stability counter"
            fi
        fi
        
        sleep $PROCESS_CHECK_INTERVAL
        elapsed=$((elapsed + PROCESS_CHECK_INTERVAL))
    done
    
    log_message "WARN" "Dock stabilization timeout reached after ${dock_timeout}s"
    log_message "INFO" "Exiting to allow user to use current dock configuration"
    exit 0
}

# Enhanced user validation with better timeout handling
wait_for_valid_user()
{
    # Don't use log_message at the start as log file might not be ready
    echo "Waiting for valid user login..."
    
    local end_time=$(($(date +%s) + USER_WAIT_TIMEOUT))
    local current_user
    local remaining
    
    while (($(date +%s) < end_time)); do
        current_user=$(get_current_user)
        
        # Skip empty or system users immediately
        [[ -z "$current_user" || "$current_user" =~ ^(root|_mbsetupuser|loginwindow)$ ]] || {
            USER_UID=$(id -u "$current_user" 2>/dev/null) && {
                LOGGED_IN_USER="$current_user"
                # Initialize log paths now that we have a user
                set_log_paths
                log_message "SUCCESS" "Valid user detected: $LOGGED_IN_USER (UID: $USER_UID)"
                return 0
            }
        }
        
        remaining=$((end_time - $(date +%s)))
        # Only use log_message if we have a user and log paths set
        if [[ -n "$LOGGED_IN_USER" && -n "$LOG_DIR" ]]; then
            log_message "INFO" "Current user '$current_user' is not valid, waiting... (${remaining}s remaining)"
        else
            echo "Current user '$current_user' is not valid, waiting... (${remaining}s remaining)"
        fi
        sleep $PROCESS_CHECK_INTERVAL
    done
    
    # Set minimal log paths for error message if not already set
    if [[ -z "$LOG_DIR" ]]; then
        # Use a different approach to avoid readonly conflicts
        set_log_paths
        # If set_log_paths still fails, use direct assignment
        if [[ -z "$LOG_DIR" ]]; then
            LOG_DIR="/tmp/$LOG_BASENAME"
            LOG_FILE="$LOG_DIR/$LOG_BASENAME.log"
        fi
    fi
    log_message "ERROR" "Timeout waiting for valid user (${USER_WAIT_TIMEOUT}s)"
    return 1
}

validate_configuration()
{
    log_message "INFO" "Validating dock configuration..."

    VALID_APPS_TO_DOCK=()
    VALID_FOLDERS_TO_DOCK=()
    VALID_WEBLOCATIONS_TO_DOCK=()
    VALID_ADDITIONAL_APPS_TO_DOCK=()
    VALID_SPACERS_TO_DOCK=()
    
    # Quick check for empty configuration
    local total_items=0
    total_items=$((${#ADD_APPS_TO_DOCK[@]} + ${#ADD_FOLDERS_TO_DOCK[@]} + 
                   ${#ADD_WEBLOCATIONS_TO_DOCK[@]} + ${#ADD_ADDITIONAL_APPS_TO_DOCK[@]} +
                   ${#ADD_SPACERS_TO_DOCK[@]}))
    if [[ "$CLEAR_DOCK_FIRST" != true ]]; then
        total_items=$((total_items + ${#REMOVE_ITEMS_FROM_DOCK[@]}))
    fi
    
    if ((total_items == 0)); then
        log_message "WARN" "No dock items configured. Exiting."
        exit 0
    fi
    
    local valid_items=0
    local invalid_items=0
    
    # Validate applications
    for app_record in "${ADD_APPS_TO_DOCK[@]}"; do
        local app_path
        app_path="$(field_at "$app_record" 0)"
        if validate_path "$app_path" "app"; then
            VALID_APPS_TO_DOCK+=("$app_record")
            ((valid_items++))
        else
            ((invalid_items++))
        fi
    done

    for app_record in "${ADD_ADDITIONAL_APPS_TO_DOCK[@]}"; do
        local app_path
        app_path="$(field_at "$app_record" 0)"
        if validate_path "$app_path" "app"; then
            VALID_ADDITIONAL_APPS_TO_DOCK+=("$app_record")
            ((valid_items++))
        else
            ((invalid_items++))
        fi
    done
    
    # Validate folders
    for folder_record in "${ADD_FOLDERS_TO_DOCK[@]}"; do
        local folder_path
        local expanded_path
        folder_path="$(field_at "$folder_record" 0)"
        expanded_path="$(resolve_user_path "$folder_path")"
        
        if validate_path "$expanded_path" "folder"; then
            VALID_FOLDERS_TO_DOCK+=("$folder_record")
            ((valid_items++))
        else
            ((invalid_items++))
        fi
    done
    
    # Validate web locations with enhanced URL validation
    for web_location in "${ADD_WEBLOCATIONS_TO_DOCK[@]}"; do
        local url label
        url="$(field_at "$web_location" 0)"
        label="$(field_at "$web_location" 1)"
        
        if validate_url "$url"; then
            if [[ -z "$label" ]]; then
                log_message "WARN" "Missing label for URL: $url, will use default"
            fi
            VALID_WEBLOCATIONS_TO_DOCK+=("$web_location")
            ((valid_items++))
        else
            log_message "WARN" "Invalid URL format or structure: $url"
            ((invalid_items++))
        fi
    done

    for spacer_record in "${ADD_SPACERS_TO_DOCK[@]}"; do
        local spacer_section
        spacer_section="$(field_at "$spacer_record" 0)"
        spacer_section="${spacer_section:-apps}"

        if [[ "$spacer_section" =~ ^(apps|others)$ ]]; then
            VALID_SPACERS_TO_DOCK+=("$spacer_record")
            ((valid_items++))
        else
            log_message "WARN" "Invalid spacer section '$spacer_section' in: $spacer_record"
            ((invalid_items++))
        fi
    done
    
    log_message "INFO" "Configuration validation: $valid_items/$total_items items valid"

    if [[ "$REQUIRE_ALL_ITEMS" == true && $invalid_items -gt 0 ]]; then
        log_message "ERROR" "$invalid_items configured item(s) were missing or invalid and REQUIRE_ALL_ITEMS=true"
        return 1
    fi
    
    if [[ $valid_items -eq 0 && "$CLEAR_DOCK_FIRST" == true ]]; then
        log_message "ERROR" "No valid dock items found in configuration"
        return 1
    fi
    
    return 0
}

build_dockutil_actions()
{
    local app_record app_path app_section app_position app_name
    local folder_record folder_path folder_view folder_display folder_sort folder_position expanded_path folder_name
    local web_location url label url_section url_position
    local spacer_record spacer_section spacer_position remove_item

    DOCKUTIL_ACTIONS=()

    if [[ "$CLEAR_DOCK_FIRST" == true ]]; then
        DOCKUTIL_ACTIONS+=("--remove" "all" "--no-restart")
    else
        for remove_item in "${REMOVE_ITEMS_FROM_DOCK[@]}"; do
            [[ -z "$remove_item" ]] && continue
            DOCKUTIL_ACTIONS+=("--remove" "$remove_item" "--no-restart")
        done
    fi

    for app_record in "${VALID_APPS_TO_DOCK[@]}"; do
        app_path="$(field_at "$app_record" 0)"
        app_section="$(field_at "$app_record" 1)"
        app_position="$(field_at "$app_record" 2)"
        app_section="${app_section:-apps}"
        app_position="${app_position:-end}"
        app_name="$(basename "$app_path" .app)"
        DOCKUTIL_ACTIONS+=(
            "--add" "$app_path"
            "--replacing" "$app_name"
            "--section" "$app_section"
        )
        append_position_args "$app_position"
        DOCKUTIL_ACTIONS+=(
            "--no-restart"
        )
    done

    for folder_record in "${VALID_FOLDERS_TO_DOCK[@]}"; do
        folder_path="$(field_at "$folder_record" 0)"
        folder_view="$(field_at "$folder_record" 1)"
        folder_display="$(field_at "$folder_record" 2)"
        folder_sort="$(field_at "$folder_record" 3)"
        folder_position="$(field_at "$folder_record" 4)"
        expanded_path="$(resolve_user_path "$folder_path")"
        folder_view="${folder_view:-grid}"
        folder_display="${folder_display:-folder}"
        folder_position="${folder_position:-end}"
        folder_name="$(basename "$expanded_path")"
        DOCKUTIL_ACTIONS+=(
            "--add" "$expanded_path"
            "--replacing" "$folder_name"
            "--section" "others"
            "--view" "$folder_view"
            "--display" "$folder_display"
        )
        if [[ -n "$folder_sort" ]]; then
            DOCKUTIL_ACTIONS+=("--sort" "$folder_sort")
        fi
        append_position_args "$folder_position"
        DOCKUTIL_ACTIONS+=(
            "--no-restart"
        )
    done

    for web_location in "${VALID_WEBLOCATIONS_TO_DOCK[@]}"; do
        url="$(field_at "$web_location" 0)"
        label="$(field_at "$web_location" 1)"
        url_section="$(field_at "$web_location" 2)"
        url_position="$(field_at "$web_location" 3)"
        label="${label:-Web Link}"
        url_section="${url_section:-others}"
        url_position="${url_position:-end}"

        DOCKUTIL_ACTIONS+=(
            "--add" "$url"
            "--label" "$label"
            "--replacing" "$label"
            "--section" "$url_section"
        )
        append_position_args "$url_position"
        DOCKUTIL_ACTIONS+=(
            "--no-restart"
        )
    done

    for app_record in "${VALID_ADDITIONAL_APPS_TO_DOCK[@]}"; do
        app_path="$(field_at "$app_record" 0)"
        app_section="$(field_at "$app_record" 1)"
        app_position="$(field_at "$app_record" 2)"
        app_section="${app_section:-apps}"
        app_position="${app_position:-end}"
        app_name="$(basename "$app_path" .app)"
        DOCKUTIL_ACTIONS+=(
            "--add" "$app_path"
            "--replacing" "$app_name"
            "--section" "$app_section"
        )
        append_position_args "$app_position"
        DOCKUTIL_ACTIONS+=(
            "--no-restart"
        )
    done

    for spacer_record in "${VALID_SPACERS_TO_DOCK[@]}"; do
        spacer_section="$(field_at "$spacer_record" 0)"
        spacer_position="$(field_at "$spacer_record" 1)"
        spacer_section="${spacer_section:-apps}"
        spacer_position="${spacer_position:-end}"

        DOCKUTIL_ACTIONS+=(
            "--add" ""
            "--type" "spacer"
            "--section" "$spacer_section"
        )
        append_position_args "$spacer_position"
        DOCKUTIL_ACTIONS+=("--no-restart")
    done

    append_dock_target_args
}

validate_runtime_options()
{
    local folder_record folder_path

    case "$DOCK_TARGET_MODE" in
        current_user|current_user_home|allhomes|home|plist|default_user_template)
            ;;
        *)
            log_message "ERROR" "Invalid DOCK_TARGET_MODE: $DOCK_TARGET_MODE"
            return 1
            ;;
    esac

    if ! target_requires_gui_user && [[ "$RUN_DOCKUTIL_AS_USER" == true ]]; then
        log_message "ERROR" "DOCK_TARGET_MODE=$DOCK_TARGET_MODE requires RUN_DOCKUTIL_AS_USER=false"
        return 1
    fi

    if ! target_requires_gui_user && [[ "$VERIFY_DOCK_CONTENTS" == true ]]; then
        log_message "WARN" "Verification requires a GUI user and will be skipped for DOCK_TARGET_MODE=$DOCK_TARGET_MODE"
    fi

    if ! target_requires_gui_user && [[ "$RESTART_DOCK" == true ]]; then
        log_message "WARN" "Dock restart requires a GUI user and will be skipped for DOCK_TARGET_MODE=$DOCK_TARGET_MODE"
    fi

    if [[ "$CLEAR_DOCK_FIRST" == true && ${#REMOVE_ITEMS_FROM_DOCK[@]} -gt 0 ]]; then
        log_message "INFO" "CLEAR_DOCK_FIRST=true; REMOVE_ITEMS_FROM_DOCK will be ignored"
    fi

    if ! target_requires_gui_user && [[ "$DOCK_TARGET_MODE" != "home" ]]; then
        for folder_record in "${ADD_FOLDERS_TO_DOCK[@]}"; do
            folder_path="$(field_at "$folder_record" 0)"
            if uses_home_placeholder "$folder_path"; then
                log_message "ERROR" "Folder path '$folder_path' uses a home placeholder, but DOCK_TARGET_MODE=$DOCK_TARGET_MODE does not provide a single home directory"
                log_message "ERROR" "Use DOCK_TARGET_MODE=home with DOCK_TARGET_HOME, or replace the folder path with an explicit path."
                return 1
            fi
        done
    fi
}

target_requires_gui_user()
{
    case "$DOCK_TARGET_MODE" in
        current_user|current_user_home)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

##################################
# Main Dock Setup Function
##################################

setup_dock()
{
    local quick_mode=${1:-false}

    if [[ "$quick_mode" == "true" ]]; then
        quick_setup_dock
        return $?
    fi
    
    if [[ "$quick_mode" != "true" ]]; then
        log_separator
        log_message "INFO" "Setting up dock for user: $LOGGED_IN_USER"
        log_separator
        
        # Ensure Downloads exists before adding it for a GUI-user workflow.
        if downloads_folder_configured && ! ensure_downloads_folder; then
            log_message "ERROR" "Failed to prepare Downloads folder"
            return 1
        fi
    fi

    if ! build_dockutil_actions; then
        log_message "ERROR" "Failed to build dockutil action batch"
        return 1
    fi
    log_message "INFO" "Applying dock changes in one dockutil run (${#DOCKUTIL_ACTIONS[@]} arguments)..."

    if ! run_with_retry run_dockutil "${DOCKUTIL_ACTIONS[@]}"; then
        log_message "ERROR" "Failed to apply dockutil action batch"
        return 1
    fi
    
    log_message "SUCCESS" "Dock items setup completed"
    return 0
}

##################################
# Error Handling
##################################

# shellcheck disable=SC2329  # Function is invoked by the EXIT trap.
cleanup()
{
    local exit_code=$?
    if [[ $# -gt 0 ]]; then
        exit_code="$1"
    fi

    local current_time
    current_time=$(date +%s)
    local total_time=$((current_time - SCRIPT_START_TIME))
    
    if [[ $exit_code -ne 0 ]]; then
        log_message "ERROR" "Script exiting with code $exit_code after $(format_duration "$total_time")"
    else
        log_message "TIMING" "Script completed successfully in $(format_duration "$total_time")"
    fi
    
    exit "$exit_code"
}

# shellcheck disable=SC2329  # Function is invoked by the ERR trap.
error_handler()
{
    local exit_code=$?
    log_message "ERROR" "Script encountered an error (exit code: $exit_code)"
    exit "$exit_code"
}

# Set up error handling and cleanup traps after defining their handlers.
trap 'error_handler' ERR
trap 'cleanup' EXIT

##################################
# Main Execution
##################################

main()
{
    SCRIPT_START_TIME=$(date +%s)

    if target_requires_gui_user; then
        # First get a valid user before initializing logs
        if ! wait_for_valid_user; then
            echo "ERROR: Failed to detect valid user"
            exit 1
        fi
    else
        LOGGED_IN_USER=""
        USER_UID=""
        set_log_paths
    fi
    
    # Initialize log location after we have a user
    set_log_paths
    
    # Ensure log directory exists with proper permissions
    if ! ensure_log_directory; then
        echo "ERROR: Failed to create log directory"
        exit 1
    fi
    
    log_message "INFO" "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    log_message "INFO" "Organization label: $ORG_NAME"
    log_separator

    if target_requires_gui_user; then
        customize_dock_items_for_user

        if dock_already_configured; then
            log_message "INFO" "Dock has already been configured for $LOGGED_IN_USER; marker exists at $(get_marker_file)"
            exit 0
        fi
    fi

    if ! validate_runtime_options; then
        log_message "ERROR" "Runtime option validation failed"
        exit 1
    fi
    
    # Pre-flight checks
    
    if ! check_dockutil; then
        log_message "ERROR" "Dockutil check failed"
        exit 1
    fi
    
    if target_requires_gui_user; then
        if ! check_required_processes; then
            log_message "ERROR" "Required process check failed"
            exit 1
        fi
    else
        log_message "INFO" "Skipping Dock/Finder readiness check for DOCK_TARGET_MODE=$DOCK_TARGET_MODE"
    fi
    
    if target_requires_gui_user; then
        if ! wait_for_valid_user; then
            log_message "ERROR" "Failed to detect valid user"
            exit 1
        fi
    fi
    
    # Update log directory permissions now that we have the user
    # This won't try to modify the readonly LOG_DIR variable
    if [[ -n "$LOGGED_IN_USER" && "$LOGGED_IN_USER" != "root" ]]; then
        ensure_log_directory
    fi
    
    if ! validate_configuration; then
        log_message "ERROR" "Configuration validation failed"
        exit 1
    fi
    
    # Main dock setup
    if ! setup_dock; then
        log_message "ERROR" "Dock setup failed"
        exit 1
    fi
    
    # Verify dock contents
    if target_requires_gui_user && [[ "$VERIFY_DOCK_CONTENTS" == true ]] && ! verify_dock_contents; then
        log_message "WARN" "Dock verification failed. Attempting one more setup in quick mode..."
        # Quick retry with minimal checks
        if ! setup_dock true; then
            log_message "ERROR" "Final dock setup attempt failed"
            exit 1
        fi
        # Verify one last time
        if ! verify_dock_contents; then
            log_message "ERROR" "Final dock verification failed"
            exit 1
        fi
    elif [[ "$VERIFY_DOCK_CONTENTS" != true ]] || ! target_requires_gui_user; then
        log_message "INFO" "Dock content verification skipped for current settings"
    fi

    # Restart the dock after all modifications
    if [[ "$RESTART_DOCK" != true ]] || ! target_requires_gui_user; then
        log_message "INFO" "Dock restart skipped for current settings"
        log_separator
        if ! write_completion_marker; then
            log_message "ERROR" "Dock setup completed, but the completion marker could not be written"
            exit 1
        fi
        log_message "SUCCESS" "Script completed successfully"
        exit 0
    fi

    log_message "INFO" "Restarting dock to apply all changes..."
    sleep $DOCK_RESTART_DELAY
    
    local restart_timeout=15
    local restart_elapsed=0
    local restart_attempts=0
    local max_restart_attempts=3
    
    while ((restart_attempts < max_restart_attempts)); do
        if ! run_as_user "$KILLALL_PATH" Dock; then
            log_message "WARN" "Failed to restart dock (attempt $((restart_attempts + 1))/$max_restart_attempts)"
            ((restart_attempts++))
            sleep 2
            continue
        fi
        break
    done
    
    if ((restart_attempts >= max_restart_attempts)); then
        log_message "ERROR" "Failed to restart dock after $max_restart_attempts attempts"
        exit 1
    fi
    
    # Wait for Dock process to come back with faster polling
    while ! is_process_running "Dock"; do
        if [[ $restart_elapsed -ge $restart_timeout ]]; then
            log_message "ERROR" "Timeout waiting for Dock to restart"
            exit 1
        fi
        sleep 1
        restart_elapsed=$((restart_elapsed + 1))
    done
    
    # Give the Dock a moment to fully initialize.
    sleep 1
    
    log_message "SUCCESS" "Dock restart completed successfully"
    log_separator

    if ! write_completion_marker; then
        log_message "ERROR" "Dock setup completed, but the completion marker could not be written"
        exit 1
    fi
    
    # Calculate and log total execution time
    local end_time
    end_time=$(date +%s)
    local total_duration=$((end_time - SCRIPT_START_TIME))
    local formatted_total_time
    formatted_total_time=$(format_duration "$total_duration")
    log_message "TIMING" "Total script execution time: $formatted_total_time"
    
    log_message "SUCCESS" "Script completed successfully"
    exit 0
}

##################################
# Verification Functions
##################################

verify_dock_contents()
{
    log_message "INFO" "Verifying dock contents..."
    
    # Get current dock items with retries
    local dock_items
    local retry_count=0
    local max_retries=3
    
    while ((retry_count < max_retries)); do
        if ! dock_items=$(run_as_user "$DOCKUTIL_PATH" --list 2>/dev/null); then
            ((retry_count++))
            if ((retry_count >= max_retries)); then
                log_message "ERROR" "Failed to get current dock items after $max_retries attempts"
                return 1
            fi
            log_message "WARN" "Failed to get dock items (attempt $retry_count/$max_retries), retrying..."
            sleep 2
            continue
        fi
        break
    done
    
    # Log the actual dock contents for debugging
    log_message "INFO" "Current dock contents:"
    while IFS= read -r line; do
        log_message "INFO" "  $line"
    done <<< "$dock_items"

    local name
    # Check all applications at once with case-insensitive matching
    for app_record in "${VALID_APPS_TO_DOCK[@]}" "${VALID_ADDITIONAL_APPS_TO_DOCK[@]}"; do
        local app_path
        app_path="$(field_at "$app_record" 0)"
        if [[ -z "$app_path" ]]; then
            continue  # Skip empty paths
        fi
        if ! name=$(basename "$app_path" .app 2>/dev/null); then
            log_message "ERROR" "Failed to get basename for: $app_path"
            return 1
        fi
        
        # Clean up the name and make it more lenient for matching
        name=$(echo "$name" | sed 's/[[:space:]]*$//; s/^[[:space:]]*//')  # Trim whitespace
        
        # Debug output to see what we're looking for
        log_message "INFO" "Checking for application: '$name' in dock items"
        
        # Try multiple matching approaches with the original name (preserving spaces and case)
        log_message "INFO" "Looking for '$name' in dock..."
        
        local found=0
        
        # Simple case-insensitive search preserving spaces
        if echo "$dock_items" | grep -Fqi "$name"; then
            log_message "INFO" "Found match for: $name"
            found=1
        fi

        if ((found == 0)); then
            log_message "ERROR" "Missing application in dock: $name"
            return 1
        fi
    done

    # Check folders
    for folder_record in "${VALID_FOLDERS_TO_DOCK[@]}"; do
        local expanded_path
        expanded_path="$(resolve_user_path "$(field_at "$folder_record" 0)")"
        name=$(basename "$expanded_path")
        if ! echo "$dock_items" | grep -Fq "$name"; then
            log_message "ERROR" "Missing folder in dock: $name"
            return 1
        fi
    done

    # Check web locations
    for web_location in "${VALID_WEBLOCATIONS_TO_DOCK[@]}"; do
        local url label found=0
        url="$(field_at "$web_location" 0)"
        label="$(field_at "$web_location" 1)"
        
        # Try to find by label first
        if [[ -n "$label" ]] && echo "$dock_items" | grep -Fq "$label"; then
            found=1
        # Fall back to URL check if label not found
        elif echo "$dock_items" | grep -Fq "$url"; then
            found=1
        # Finally check for default Web Link label
        elif [[ -z "$label" ]] && echo "$dock_items" | grep -Fq "Web Link"; then
            found=1
        fi
        
        if ((found == 0)); then
            log_message "ERROR" "Missing web location in dock: ${label:-$url}"
            return 1
        fi
    done

    log_message "SUCCESS" "All configured items verified in dock"
    return 0
}

##################################
# Quick Setup Function
##################################

# shellcheck disable=SC2317  # Function is called indirectly through setup_dock with quick_mode=true.
quick_setup_dock()
{
    # Skip repeat validation and most logging - this is a fast, last-resort attempt.
    log_message "INFO" "Quick setup: Clearing dock and adding items..."

    if ! build_dockutil_actions; then
        log_message "ERROR" "Quick setup failed to build dockutil action batch"
        return 1
    fi

    if ! run_dockutil "${DOCKUTIL_ACTIONS[@]}"; then
        log_message "ERROR" "Quick setup failed to apply dockutil action batch"
        return 1
    fi

    # Immediate restart for GUI-user workflows.
    if [[ "$RESTART_DOCK" == true ]]; then
        run_as_user "$KILLALL_PATH" Dock
    fi

    return 0
}

# Run main function
main "$@"
