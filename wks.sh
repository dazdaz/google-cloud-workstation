#!/bin/bash
#
# Google Cloud Workstations Management Script
# 
# A utility script to manage Google Cloud Workstations from the command line.
# Supports: start, stop, create, ssh, status, and list operations.
#

set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration file if it exists
if [[ -f "${SCRIPT_DIR}/config.sh" ]]; then
    source "${SCRIPT_DIR}/config.sh"
fi

# Colors for output (using $'...' for proper escape sequence interpretation)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color

# Default values from environment variables
CLUSTER="${WORKSTATION_CLUSTER:-}"
CONFIG="${WORKSTATION_CONFIG:-}"
REGION="${WORKSTATION_REGION:-}"
PROJECT="${WORKSTATION_PROJECT:-}"
DRY_RUN=false
VERBOSE=false

# Script name for help messages
SCRIPT_NAME=$(basename "$0")

# Browser paths for macOS
BROWSER_CHROME="/Applications/Google Chrome.app"
BROWSER_CHROME_CANARY="/Applications/Google Chrome Canary.app"
BROWSER_FIREFOX="/Applications/Firefox.app"
BROWSER_BRAVE="/Applications/Brave Browser.app"

# =============================================================================
# Helper Functions
# =============================================================================

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_step() {
    echo -e "${BLUE}→${NC} $1"
}

# Show usage information
show_help() {
    cat << EOF
${BLUE}Google Cloud Workstations Management Script${NC}

${YELLOW}USAGE:${NC}
    $SCRIPT_NAME <command> [workstation-name] [options]

${YELLOW}COMMANDS:${NC}
    start   <name>    Start an existing workstation
    stop    <name>    Stop a running workstation
    restart <name>    Restart a workstation (to apply new image)
    create  <name>    Create a new workstation
    delete  <name>    Delete a workstation
    ssh     <name>    SSH into a running workstation
    status  <name>    Check workstation status
    list              List all workstations in the configuration

${YELLOW}OPTIONS:${NC}
    -c, --cluster <name>     Workstation cluster name
    -f, --config <name>      Workstation configuration name
    -r, --region <region>    GCP region (e.g., us-central1)
    -p, --project <id>       GCP project ID
    -v, --verbose            Show commands being executed
    --dry-run                Show commands without executing
    -h, --help               Show this help message

${YELLOW}ENVIRONMENT VARIABLES:${NC}
    WORKSTATION_CLUSTER      Default cluster name
    WORKSTATION_CONFIG       Default configuration name
    WORKSTATION_REGION       Default region
    WORKSTATION_PROJECT      Default project ID (optional, uses gcloud default)

${YELLOW}EXAMPLES:${NC}
    # Set defaults via environment variables
    export WORKSTATION_CLUSTER="my-cluster"
    export WORKSTATION_CONFIG="my-config"
    export WORKSTATION_REGION="us-central1"

    # Start a workstation
    $SCRIPT_NAME start my-workstation

    # Create a new workstation
    $SCRIPT_NAME create my-new-workstation

    # SSH into a workstation
    $SCRIPT_NAME ssh my-workstation

    # Override defaults with flags
    $SCRIPT_NAME start my-workstation -c other-cluster -r europe-west1

    # List all workstations
    $SCRIPT_NAME list

EOF
}

# Check if gcloud is installed
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install the Google Cloud SDK."
        exit 1
    fi
}

# Validate required parameters
validate_params() {
    local require_name=${1:-true}
    local errors=0

    if [[ "$require_name" == "true" && -z "${WORKSTATION_NAME:-}" ]]; then
        print_error "Workstation name is required."
        errors=$((errors + 1))
    fi

    if [[ -z "$CLUSTER" ]]; then
        print_error "Cluster name is required. Set WORKSTATION_CLUSTER or use -c flag."
        errors=$((errors + 1))
    fi

    if [[ -z "$CONFIG" ]]; then
        print_error "Configuration name is required. Set WORKSTATION_CONFIG or use -f flag."
        errors=$((errors + 1))
    fi

    if [[ -z "$REGION" ]]; then
        print_error "Region is required. Set WORKSTATION_REGION or use -r flag."
        errors=$((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        echo ""
        show_help
        exit 1
    fi
}

# Prompt user to open URL in browser
prompt_open_browser() {
    local url="$1"
    
    # Build arrays of browser IDs and names
    local browser_ids=()
    local browser_names=()
    
    if [[ -d "$BROWSER_CHROME" ]]; then
        browser_ids+=("chrome")
        browser_names+=("Google Chrome")
    fi
    
    if [[ -d "$BROWSER_CHROME_CANARY" ]]; then
        browser_ids+=("canary")
        browser_names+=("Google Chrome Canary")
    fi
    
    if [[ -d "$BROWSER_FIREFOX" ]]; then
        browser_ids+=("firefox")
        browser_names+=("Firefox")
    fi
    
    if [[ -d "$BROWSER_BRAVE" ]]; then
        browser_ids+=("brave")
        browser_names+=("Brave Browser")
    fi
    
    if [[ ${#browser_ids[@]} -eq 0 ]]; then
        print_warning "No supported browsers detected."
        return 0
    fi
    
    echo ""
    read -p "Would you like to open the workstation in a browser? [y/N] " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 0
    fi
    
    # If only one browser, use it directly
    if [[ ${#browser_ids[@]} -eq 1 ]]; then
        open_in_browser "${browser_ids[0]}" "$url"
        return 0
    fi
    
    # Multiple browsers - let user choose
    echo ""
    print_info "Available browsers:"
    local i=1
    for name in "${browser_names[@]}"; do
        echo "  $i) $name"
        i=$((i + 1))
    done
    echo ""
    
    read -p "Select a browser [1-${#browser_ids[@]}]: " -r choice
    
    # Validate choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#browser_ids[@]} ]]; then
        print_warning "Invalid selection. Skipping browser launch."
        return 0
    fi
    
    local selected_id="${browser_ids[$((choice - 1))]}"
    open_in_browser "$selected_id" "$url"
}

# Open URL in specified browser
open_in_browser() {
    local browser_id="$1"
    local url="$2"
    local app_name=""
    
    case "$browser_id" in
        chrome)
            app_name="Google Chrome"
            ;;
        canary)
            app_name="Google Chrome Canary"
            ;;
        firefox)
            app_name="Firefox"
            ;;
        brave)
            app_name="Brave Browser"
            ;;
        *)
            print_error "Unknown browser: $browser_id"
            return 1
            ;;
    esac
    
    print_info "Opening in $app_name..."
    if open -a "$app_name" "$url" 2>/dev/null; then
        print_success "Browser launched successfully."
    else
        print_error "Failed to open browser. You can manually open: $url"
    fi
}

# Build common gcloud flags
build_gcloud_flags() {
    local flags="--cluster=$CLUSTER --config=$CONFIG --region=$REGION"
    if [[ -n "$PROJECT" ]]; then
        flags="$flags --project=$PROJECT"
    fi
    echo "$flags"
}

# Run a gcloud command (or show it in dry-run mode)
run_gcloud() {
    local cmd="gcloud $*"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "${YELLOW}[DRY-RUN]${NC} $cmd"
        return 0
    else
        if [[ "$VERBOSE" == "true" ]]; then
            echo "${BLUE}[CMD]${NC} $cmd"
        fi
        eval "$cmd"
    fi
}

# =============================================================================
# Command Implementations
# =============================================================================

# Start a workstation
cmd_start() {
    validate_params
    local flags=$(build_gcloud_flags)

    print_info "Starting workstation '$WORKSTATION_NAME'..."
    
    if run_gcloud workstations start "$WORKSTATION_NAME" $flags; then
        print_success "Workstation '$WORKSTATION_NAME' is starting."
        print_info "Waiting for workstation to be ready..."
        
        # Poll for RUNNING state
        local max_attempts=60
        local attempt=0
        while [[ $attempt -lt $max_attempts ]]; do
            if [[ "$DRY_RUN" == "true" ]]; then
                echo ""
                print_success "[DRY-RUN] Workstation would start here."
                return 0
            fi
            local state=$(gcloud workstations describe "$WORKSTATION_NAME" $flags --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            if [[ "$state" == "STATE_RUNNING" ]]; then
                echo ""
                print_success "Workstation '$WORKSTATION_NAME' is now running!"
                echo ""
                
                # Get the workstation URL
                local host=$(gcloud workstations describe "$WORKSTATION_NAME" $flags --format="value(host)" 2>/dev/null || echo "")
                if [[ -n "$host" ]]; then
                    local web_url="https://$host"
                    print_info "Web URL:     $web_url"
                fi
                
                # Print the SSH command
                local ssh_cmd="gcloud workstations ssh $WORKSTATION_NAME --cluster=$CLUSTER --config=$CONFIG --region=$REGION"
                if [[ -n "$PROJECT" ]]; then
                    ssh_cmd="$ssh_cmd --project=$PROJECT"
                fi
                print_info "SSH command: $ssh_cmd"
                print_info "        or:  $SCRIPT_NAME ssh $WORKSTATION_NAME"
                
                # Offer to open in browser
                if [[ -n "${web_url:-}" ]]; then
                    prompt_open_browser "$web_url"
                fi
                
                return 0
            fi
            printf "."
            sleep 5
            attempt=$((attempt + 1))
        done
        
        print_warning "Workstation may still be starting. Check status with: $SCRIPT_NAME status $WORKSTATION_NAME"
    else
        print_error "Failed to start workstation '$WORKSTATION_NAME'."
        exit 1
    fi
}

# Stop a workstation
cmd_stop() {
    validate_params
    local flags=$(build_gcloud_flags)

    print_info "Stopping workstation '$WORKSTATION_NAME'..."
    
    if run_gcloud workstations stop "$WORKSTATION_NAME" $flags; then
        print_success "Workstation '$WORKSTATION_NAME' is stopping."
    else
        print_error "Failed to stop workstation '$WORKSTATION_NAME'."
        exit 1
    fi
}

# Restart a workstation (useful after image updates)
cmd_restart() {
    validate_params
    local flags=$(build_gcloud_flags)

    # Check if workstation exists
    local current_state=$(gcloud workstations describe "$WORKSTATION_NAME" $flags --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$current_state" == "NOT_FOUND" ]]; then
        print_error "Workstation '$WORKSTATION_NAME' does not exist."
        print_info "Create it first with: $SCRIPT_NAME create $WORKSTATION_NAME"
        exit 1
    fi

    print_info "Restarting workstation '$WORKSTATION_NAME'..."
    print_info "This will apply any updated container image."
    print_info "(Note: Restart typically takes 2-5 minutes)"
    echo ""
    
    if [[ "$current_state" == "STATE_STOPPED" ]]; then
        print_info "Workstation is already stopped."
    else
        # Stop the workstation
        print_step "Step 1/2: Stopping workstation..."
        if gcloud workstations stop "$WORKSTATION_NAME" $flags 2>/dev/null; then
            # Wait for it to stop
            print_info "Waiting for workstation to stop (this may take 1-2 minutes)..."
            local max_attempts=60
            local attempt=0
            while [[ $attempt -lt $max_attempts ]]; do
                local state=$(gcloud workstations describe "$WORKSTATION_NAME" $flags --format="value(state)" 2>/dev/null || echo "UNKNOWN")
                if [[ "$state" == "STATE_STOPPED" ]]; then
                    echo ""
                    print_success "Workstation stopped."
                    break
                fi
                printf "."
                sleep 3
                attempt=$((attempt + 1))
            done
            echo ""
        else
            print_warning "Stop command returned error - workstation may already be stopping."
        fi
    fi
    
    # Start the workstation
    echo ""
    print_step "Step 2/2: Starting workstation with new image..."
    cmd_start
}

# Create a new workstation
cmd_create() {
    validate_params
    local flags=$(build_gcloud_flags)

    print_info "Creating workstation '$WORKSTATION_NAME'..."
    print_info "  Cluster: $CLUSTER"
    print_info "  Config:  $CONFIG"
    print_info "  Region:  $REGION"
    [[ -n "$PROJECT" ]] && print_info "  Project: $PROJECT"
    
    if run_gcloud workstations create "$WORKSTATION_NAME" $flags; then
        if [[ "$DRY_RUN" == "true" ]]; then
            return 0
        fi
        echo ""
        print_success "Workstation '$WORKSTATION_NAME' created successfully!"
        echo ""
        
        # Get the workstation URL
        local host=$(gcloud workstations describe "$WORKSTATION_NAME" $flags --format="value(host)" 2>/dev/null || echo "")
        if [[ -n "$host" ]]; then
            print_info "Web URL:     https://$host"
        fi
        
        # Print the SSH command
        local ssh_cmd="gcloud workstations ssh $WORKSTATION_NAME --cluster=$CLUSTER --config=$CONFIG --region=$REGION"
        if [[ -n "$PROJECT" ]]; then
            ssh_cmd="$ssh_cmd --project=$PROJECT"
        fi
        print_info "SSH command: $ssh_cmd"
        print_info "        or:  $SCRIPT_NAME ssh $WORKSTATION_NAME"
        echo ""
        print_info "The workstation should start automatically."
    else
        print_error "Failed to create workstation '$WORKSTATION_NAME'."
        exit 1
    fi
}

# SSH into a workstation
cmd_ssh() {
    validate_params
    local flags=$(build_gcloud_flags)

    # Check if workstation is running
    local state=$(gcloud workstations describe "$WORKSTATION_NAME" $flags --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$state" != "STATE_RUNNING" ]]; then
        print_warning "Workstation '$WORKSTATION_NAME' is not running (state: $state)."
        read -p "Would you like to start it first? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cmd_start
        else
            print_error "Cannot SSH into a non-running workstation."
            exit 1
        fi
    fi

    print_info "Connecting to workstation '$WORKSTATION_NAME' via SSH..."
    
    run_gcloud workstations ssh "$WORKSTATION_NAME" $flags
}

# Show workstation status
cmd_status() {
    validate_params
    local flags=$(build_gcloud_flags)

    print_info "Getting status for workstation '$WORKSTATION_NAME'..."
    
    if ! run_gcloud workstations describe "$WORKSTATION_NAME" $flags --format='"table(
        name.basename():label=NAME,
        state:label=STATE,
        host:label=HOST,
        createTime.date():label=CREATED,
        updateTime.date():label=UPDATED
    )"'; then
        print_error "Failed to get status for workstation '$WORKSTATION_NAME'."
        exit 1
    fi
}

# Delete a workstation
cmd_delete() {
    validate_params
    local flags=$(build_gcloud_flags)

    print_warning "This will permanently delete workstation '$WORKSTATION_NAME'!"
    print_warning "All data stored in the workstation will be lost."
    echo ""
    read -p "Are you sure you want to delete '$WORKSTATION_NAME'? [y/N] " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Delete cancelled."
        exit 0
    fi

    print_info "Deleting workstation '$WORKSTATION_NAME'..."
    
    if run_gcloud workstations delete "$WORKSTATION_NAME" $flags --quiet; then
        print_success "Workstation '$WORKSTATION_NAME' deleted successfully."
    else
        print_error "Failed to delete workstation '$WORKSTATION_NAME'."
        exit 1
    fi
}

# List all workstations
cmd_list() {
    validate_params false
    local flags=$(build_gcloud_flags)

    print_info "Listing workstations..."
    print_info "  Cluster: $CLUSTER"
    print_info "  Config:  $CONFIG"
    print_info "  Region:  $REGION"
    echo ""
    
    if ! run_gcloud workstations list $flags --format='"table(
        name.basename():label=NAME,
        state:label=STATE,
        host:label=HOST,
        createTime.date():label=CREATED
    )"'; then
        print_error "Failed to list workstations."
        exit 1
    fi
}

# =============================================================================
# Main Script
# =============================================================================

main() {
    check_gcloud

    # Parse command (first argument)
    COMMAND="${1:-}"
    shift || true

    # Handle help flag first
    if [[ "$COMMAND" == "-h" || "$COMMAND" == "--help" || -z "$COMMAND" ]]; then
        show_help
        exit 0
    fi

    # For non-list commands, get the workstation name
    if [[ "$COMMAND" != "list" ]]; then
        WORKSTATION_NAME="${1:-}"
        shift || true
    fi

    # Parse remaining options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--cluster)
                CLUSTER="$2"
                shift 2
                ;;
            -f|--config)
                CONFIG="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Execute the appropriate command
    case "$COMMAND" in
        start)
            cmd_start
            ;;
        stop)
            cmd_stop
            ;;
        restart)
            cmd_restart
            ;;
        create)
            cmd_create
            ;;
        delete)
            cmd_delete
            ;;
        ssh)
            cmd_ssh
            ;;
        status)
            cmd_status
            ;;
        list)
            cmd_list
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

main "$@"