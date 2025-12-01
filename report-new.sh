#!/bin/bash
set -o pipefail

# Source library files
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/azure-devops.sh"
source "$(dirname "$0")/lib/github.sh"

START_DATE=$(date +%Y-%m-01T00:00:00.000000+00:00)

# parse options
DEBUG=0
SILENT=0
SOURCES=() # array of sources to use

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mode)
            shift
            case $1 in
                debug) DEBUG=1; SILENT=0; print_debug "We run in debug mode" ;;
                silent) DEBUG=0; SILENT=1 ;;
                *) print_error "Invalid mode: $1, values are 'debug' or 'silent'"; exit 1 ;;
            esac
            ;;
        --source)
            shift
            case $1 in
                azure|github|both) 
                    if [ "$1" == "both" ]; then
                        SOURCES=("azure" "github")
                    else
                        SOURCES=("$1")
                    fi
                    ;;
                *) print_error "Invalid source: $1, values are 'azure', 'github', or 'both'"; exit 1 ;;
            esac
            ;;
    esac
    shift
done

# Default to both sources if none specified
if [ ${#SOURCES[@]} -eq 0 ]; then
    SOURCES=("azure" "github")
fi

# Validate common environment variables
if [ -z "$AUTHOR_EMAIL" ]; then
    print_error "Environment variable AUTHOR_EMAIL is not set"
    exit 1
fi

if [ -n "$MANAGER" ]; then
    print_warning "Obsolete MANAGER environment variable, provide MANAGER_EMAIL instead"
    exit 1
fi

if [ -z "$MANAGER_EMAIL" ]; then
    print_error "Environment variable MANAGER_EMAIL is not set"
    exit 1
fi

# Validate source-specific environment variables for each enabled source
for source in "${SOURCES[@]}"; do
    if [ "$source" == "azure" ]; then
        if ! validate_azure_devops_env 2>/dev/null; then
            print_warning "Azure DevOps environment not configured, skipping Azure DevOps"
            SOURCES=("${SOURCES[@]/$source}")
        fi
    elif [ "$source" == "github" ]; then
        if ! validate_github_env 2>/dev/null; then
            print_warning "GitHub environment not configured, skipping GitHub"
            SOURCES=("${SOURCES[@]/$source}")
        fi
    fi
done

# Check if we have at least one valid source
SOURCES=("${SOURCES[@]}")  # Remove empty elements
if [ ${#SOURCES[@]} -eq 0 ]; then
    print_error "No valid sources configured. Please set up at least one source."
    exit 1
fi

validate_output_directory

#variables
TOTAL_HOURS="0.0"
LINE_NUMBER="1"
KUP_PATTERN='(?<=\[KUP:)\s*\d+([\.,]\d+)?(?=\])'
declare -A KNOWN_COMMITS

# reading input parameters
PARAM_MONTH=$(date -d "$START_DATE" +%B)
PARAM_DAYS=$(sed -n "$(date +%m)p" calendar.txt | cut -f2 -d '|')
PARAM_ABS="0"

if (( SILENT == 0 )); then
    if [ -z "$PARAM_DAYS" ]; then
        echo -n 'Working days in the Period: '
        read -r PARAM_DAYS
    else
        print_text "Working days in the Period: $PARAM_DAYS"
    fi

    echo -n 'Authors days of absence: '
    read -r PARAM_ABS
fi 

rm -f "_lines.txt"

# Initialize display names
AUTHOR_DISPLAY=""
MANAGER_DISPLAY=""

# Get author and manager information from the first available source
for source in "${SOURCES[@]}"; do
    if [ "$source" == "azure" ] && [ -z "$AUTHOR_DISPLAY" ]; then
        AUTH=$(echo -n "$AUTHOR_EMAIL:$AZURE_DEVOPS_EXT_PAT" | base64 -w 0)
        print_debug "AZURE_DEVOPS_EXT_PAT = $AZURE_DEVOPS_EXT_PAT"
        print_debug "AUTH = $AUTH"

        AUTHOR=$(get_azure_devops_author "$AUTHOR_EMAIL")
        AUTHOR_ID=$(jq -r '.id' <<< "$AUTHOR")
        AUTHOR_DISPLAY=$(jq -r '.user.displayName' <<< "$AUTHOR")

        MANAGER=$(get_azure_devops_manager "$MANAGER_EMAIL")
        MANAGER_DISPLAY=$(jq -r '.user.displayName' <<< "$MANAGER")
    elif [ "$source" == "github" ] && [ -z "$AUTHOR_DISPLAY" ]; then
        print_debug "GITHUB_TOKEN = $GITHUB_TOKEN"
        print_debug "GITHUB_ORG = $GITHUB_ORG"

        # For GitHub, we need to extract the display name differently
        # We'll use the email directly and get the name from API if needed
        AUTHOR_DISPLAY=${AUTHOR_NAME:-$AUTHOR_EMAIL}
        MANAGER_DISPLAY=${MANAGER_NAME:-$MANAGER_EMAIL}
    fi
done

print_text
print_text "AUTHOR: $AUTHOR_DISPLAY"
print_text "AUTHOR_TITLE: $AUTHOR_TITLE"
print_text "MANAGER: $MANAGER_DISPLAY"
print_text "MANAGER_TITLE: $MANAGER_TITLE"
print_text "SOURCES: ${SOURCES[*]}"
print_text

print_text "Searching PRs from $START_DATE..."

# Collect PRs from all sources
for source in "${SOURCES[@]}"; do
    print_text
    print_text "========================================="
    print_text "Collecting from: $source"
    print_text "========================================="
    
    if [ "$source" == "azure" ]; then
        SOURCE_HOURS=$(collect_azure_devops_prs "$AUTHOR_ID" "$START_DATE" "$KUP_PATTERN" "$AUTH" "$MANAGER_EMAIL" "$MANAGER_DISPLAY" "$LINE_NUMBER")
        print_success "Azure DevOps: Collected $SOURCE_HOURS hours"
        TOTAL_HOURS=$(awk "BEGIN {printf \"%.2f\", $TOTAL_HOURS + $SOURCE_HOURS}")
        
        # Update line number for next source
        LINE_NUMBER=$(wc -l < "_lines.txt" 2>/dev/null | awk '{print int($1/2) + 1}' || echo "$LINE_NUMBER")
    elif [ "$source" == "github" ]; then
        SOURCE_HOURS=$(collect_github_prs "$AUTHOR_EMAIL" "$START_DATE" "$KUP_PATTERN" "$GITHUB_TOKEN" "$GITHUB_ORG" "$MANAGER_EMAIL" "$MANAGER_DISPLAY" "$LINE_NUMBER")
        print_success "GitHub: Collected $SOURCE_HOURS hours"
        TOTAL_HOURS=$(awk "BEGIN {printf \"%.2f\", $TOTAL_HOURS + $SOURCE_HOURS}")
        
        # Update line number for next source
        LINE_NUMBER=$(wc -l < "_lines.txt" 2>/dev/null | awk '{print int($1/2) + 1}' || echo "$LINE_NUMBER")
    fi
done

print_text
print_text "========================================="
print_success "Total hours from all sources: $TOTAL_HOURS"
print_text "========================================="

# Print summary
print_summary "$TOTAL_HOURS" "$PARAM_DAYS" "$PARAM_ABS"

# stop program if we are in silent mode
if (( SILENT == 1 )); then
    exit 0
fi

# Generate PDF report
generate_pdf_report "$AUTHOR_DISPLAY" "$AUTHOR_TITLE" "$MANAGER_DISPLAY" "$MANAGER_TITLE" "$PARAM_MONTH" "$PARAM_DAYS" "$PARAM_ABS"
