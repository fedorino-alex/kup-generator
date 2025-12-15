#!/bin/bash
# Common functions and utilities used across all scripts

function print_error() {
    local ECHO_RED='\033[0;31m'       # errors color
    local ECHO_NC='\033[0m'           # No Color or just text

    if (( SILENT == 0 )); then
        echo -e "${ECHO_RED}$1${ECHO_NC}" >&2
    fi
}

function print_info() {
    local ECHO_CYAN='\033[0;36m'      # warning color
    local ECHO_NC='\033[0m'           # No Color or just text

    if (( SILENT == 0 )); then
        echo -e "${ECHO_CYAN}$1${ECHO_NC}" >&2
    fi
}

function print_warning() {
    local ECHO_YELLOW='\033[0;33m'    # info color
    local ECHO_NC='\033[0m'           # No Color or just text

    if (( SILENT == 0 )); then
        echo -e "${ECHO_YELLOW}$1${ECHO_NC}" >&2
    fi
}

function print_debug() {
    local ECHO_GREY='\033[0;90m'      # debug color
    local ECHO_NC='\033[0m'           # No Color or just text

    if (( DEBUG == 1 && SILENT == 0 )); then
        echo -e "${ECHO_GREY}DEBUG: $1${ECHO_NC}" >&2
    fi
}

function print_success() {
    local ECHO_GREEN='\033[0;32m'     # success color
    local ECHO_NC='\033[0m'           # No Color or just text

    if (( SILENT == 0 )); then
        echo -e "${ECHO_GREEN}$1${ECHO_NC}" >&2
    fi
}

function print_text() {
    if (( SILENT == 0 )); then
        echo -e "$1" >&2
    fi
}

function validate_output_directory() {
    if [ ! -d ./out ]; then
        print_error "Please mount output volume '{host_dir}:$(pwd)/out:rw'"
        exit 1
    fi
}

function generate_pdf_report() {
    local author_display=$1
    local author_title=$2
    local manager_display=$3
    local manager_title=$4
    local param_month=$5
    local param_days=$6
    local param_abs=$7

    print_text

    MONTH_TEMPLATE_FILE="$author_display, $(date +%Y-%m).tex"
    cp -f "kup_report_template.tex" "$(pwd)/out/$MONTH_TEMPLATE_FILE"
    print_text "Report template copied to $(pwd)/out/$MONTH_TEMPLATE_FILE"

    # replace ==PLACEHOLDERS== with their values
    sed -i \
        -e "s|==AUTHOR==|$author_display|" \
        -e "s|==AUTHOR_TITLE==|$author_title|" \
        -e "s|==MANAGER==|$manager_display|" \
        -e "s|==MANAGER_TITLE==|$manager_title|" \
        -e "s|==MONTH==|$param_month|" \
        -e "s|==DAYS==|$param_days|" \
        -e "s|==ABS==|$param_abs|" \
        -e "/==LINES==/{r _lines.txt
        d}" \
        "./out/$MONTH_TEMPLATE_FILE"

    if (( DEBUG == 1 )); then
        # Run pdf creation
        pdflatex -interaction=batchmode -output-directory=./out "./out/$MONTH_TEMPLATE_FILE"
    else
        # Run pdf creation
        pdflatex -interaction=batchmode -output-directory=./out "./out/$MONTH_TEMPLATE_FILE" > /dev/null 2>&1

        # remove everything except PDF
        find ./out/ -maxdepth 1 -type f ! -name '*.pdf' -exec rm -f {} +
    fi
}

function print_summary() {
    local total_hours=$1
    local param_days=$2
    local param_abs=$3

    # Calculate percentage using awk for floating-point arithmetic
    TOTAL_EXPECTED_HOURS=$((param_days * 8))
    PERSONAL_REPORTED_HOURS=$((TOTAL_EXPECTED_HOURS - param_abs * 8))
    PERSONAL_PERCENTAGE=$(awk "BEGIN {printf \"%.2f\", ($total_hours * 100) / $PERSONAL_REPORTED_HOURS}")
    OVERALL_PERCENTAGE=$(awk "BEGIN {printf \"%.2f\", ($total_hours * 100) / $TOTAL_EXPECTED_HOURS}")

    print_success
    print_success "PRs have been collected!"

    print_info # empty line
    if (( $(awk "BEGIN {print ($PERSONAL_PERCENTAGE > 70)}") )); then
        print_error
        print_error "You worked hard for $total_hours hours of $PERSONAL_REPORTED_HOURS (including $param_abs days of absence) reported in this month and have personal busy $PERSONAL_PERCENTAGE%."
        print_error "Sorry, but this is TOO MUCH (> 70%) and very suspicious, your report will be rejected by HRs!!!"
        print_error
    else
        print_success
        print_success "You worked for $total_hours hours of $PERSONAL_REPORTED_HOURS (including $param_abs days of absence) reported in this month and have personal busy $PERSONAL_PERCENTAGE%."
        print_success "Nice."
        print_success
    fi

    # Compare using awk for floating-point comparisons
    if (( $(awk "BEGIN {print ($OVERALL_PERCENTAGE < 25)}") )); then
        print_error
        print_error "Total hours for this month (without your personal absences):"
        print_error "\t$total_hours of $TOTAL_EXPECTED_HOURS ($OVERALL_PERCENTAGE%)"
    elif (( $(awk "BEGIN {print ($OVERALL_PERCENTAGE < 50)}") )); then
        print_warning
        print_warning "Total hours for this month (without your personal absences):"
        print_warning "\t$total_hours of $TOTAL_EXPECTED_HOURS ($OVERALL_PERCENTAGE%)"
    elif (( $(awk "BEGIN {print ($OVERALL_PERCENTAGE > 70)}") )); then
        print_error
        print_error "TOO MUCH!!! Total hours for this month (without your personal absences):"
        print_error "\t$total_hours of $TOTAL_EXPECTED_HOURS ($OVERALL_PERCENTAGE%)"
    else
        print_success
        print_success "Total hours for this month (without your personal absences):"
        print_success "\t$total_hours of $TOTAL_EXPECTED_HOURS ($OVERALL_PERCENTAGE%)"
    fi
}
