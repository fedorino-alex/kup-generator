#!/bin/bash
set -o pipefail

# constants
ECHO_RED='\033[0;31m'       # errors color
ECHO_GREEN='\033[0;32m'     # success color
ECHO_YELLOW='\033[0;33m'    # info color
ECHO_CYAN='\033[0;36m'      # warning color
ECHO_GREY='\033[0;90m'      # debug color
ECHO_NC='\033[0m'           # No Color or just text

START_DATE=$(date +%Y-%m-01T00:00:00.000000+00:00)

# parse options
DEBUG=0
SILENT=0

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --mode)
            shift
            case $1 in
                debug) DEBUG=1; SILENT=0; echo -e "${ECHO_GREY}DEBUG: We run in debug mode${ECHO_NC}" ;;
                silent) DEBUG=0; SILENT=1 ;;
                *) echo -e "${ECHO_RED}Invalid mode: $1, values are 'debug' or 'silent'${ECHO_NC}"; exit 1 ;;
            esac
            ;;
    esac
    shift
done

function print_error() {
    local text="$1"
    if [[ "$SILENT" == 0 ]]; then
        echo -e "${ECHO_RED}$text${ECHO_NC}"
    fi
}

function print_warning() {
    local text="$1"
    if [[ "$SILENT" == 0 ]]; then
        echo -e "${ECHO_CYAN}$text${ECHO_NC}"
    fi
}

function print_info() {
    local text="$1"
    if [[ "$SILENT" == 0 ]]; then
        echo -e "${ECHO_YELLOW}$text${ECHO_NC}"
    fi
}

function print_debug() {
    local text="$1"
    if [[ "$DEBUG" == 1 && "$SILENT" == 0 ]]; then
        echo -e "${ECHO_GREY}DEBUG: $text${ECHO_NC}"
    fi
}

function print_success() {
    local text="$1"
    if [[ "$SILENT" == 0 ]]; then
        echo -e "${ECHO_GREEN}$text${ECHO_NC}"
    fi
}

function print_text() {
    local text="$1"
    if [[ "$SILENT" == 0 ]]; then
        echo -e "$text"
    fi
}

# environment variables
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

if [ -z "$AZURE_DEVOPS_EXT_PAT" ]; then
    print_error "Environment variable AZURE_DEVOPS_EXT_PAT is not set"
    exit 1
fi

if [ ! -d ./out ]; then
    print_error "Please mount output volume '{host_dir}:$(pwd)/out:rw'"
    exit 1
fi

#variables
AUTH=$(echo -n "$AUTHOR_EMAIL:$AZURE_DEVOPS_EXT_PAT" | base64 -w 0)

print_debug "AZURE_DEVOPS_EXT_PAT = $AZURE_DEVOPS_EXT_PAT"
print_debug "AUTH = $AUTH"

TOTAL_HOURS="0"
LINE_NUMBER="1"
KUP_PATTERN='(?<=\[KUP:)\s*\d+([\.,]\d+)?(?=\])'
declare -A KNOWN_COMMITS

# reading input parameters
PARAM_MONTH=$(date -d "$START_DATE" +%B)
PARAM_DAYS=$(sed -n "$(date +%m)p" calendar.txt | cut -f2 -d '|')

if [[ "$SILENT" == 0 ]]; then 
    if [ -z "$PARAM_DAYS" ]; then
        echo -n 'Working days in the Period: '
        read -r PARAM_DAYS
    else
        print_text "Working days in the Period: $PARAM_DAYS"
    fi

    if [ -z "$PARAM_ABS" ]; then
        echo -n 'Authors days of absence: '
        read -r PARAM_ABS
    fi
fi 

rm -f "_lines.txt"

# get author id and print_text name

AUTHOR=$(az devops user list --top 500 | jq '.members[] | select(.user.mailAddress | ascii_downcase == ("'"$AUTHOR_EMAIL"'" | ascii_downcase))' -)
AUTHOR_ID=$(jq -r '.id' <<< "$AUTHOR")
AUTHOR_DISPLAY=$(jq -r '.user.displayName' <<< "$AUTHOR")

if [ -z "$AUTHOR" ]; then
    print_error "Cannot find author by email $AUTHOR_EMAIL, your PAT is not valid or user is not exist"
    exit 1
fi

MANAGER=$(az devops user list --top 500 | jq '.members[] | select(.user.mailAddress | ascii_downcase == ("'"$MANAGER_EMAIL"'" | ascii_downcase))' -)
MANAGER_DISPLAY=$(jq -r '.user.displayName' <<< "$MANAGER")

if [ -z "$MANAGER" ]; then
    print_error "Cannot find manager by email $MANAGER_EMAIL, your PAT is not valid or user is not exist"
    exit 1
fi

print_text
print_text "AUTHOR: $AUTHOR_DISPLAY"
print_text "AUTHOR_TITLE: $AUTHOR_TITLE"
print_text "MANAGER: $MANAGER_DISPLAY"
print_text "MANAGER_TITLE: $MANAGER_TITLE"
print_text

print_text "Searching PRs from $START_DATE..."

function check_pr_title() {
    local pr=$1
    local title

    title=$(jq -r '.title' <<< "$pr")
    HOURS=$(grep -iPo -m 1 "$KUP_PATTERN" <<< "$title" | head -n1 | xargs)

    print_debug # empty line
    print_debug "PR title HOURS = [$HOURS]" 

    if [ -n "$HOURS" ]; then
        print_info "Hours found in PR Title"
    fi
}

function check_pr_description() {
    local pr=$1
    local description

    description=$(jq -r '.description' <<< "$pr")
    HOURS=$(grep -iPo -m 1 "$KUP_PATTERN" <<< "$description" | head -n1 | xargs)

    print_debug # empty line
    print_debug "PR description HOURS = [$HOURS]" 

    if [ -n "$HOURS" ]; then
        print_info "Hours found in PR Description"
    fi
}

function check_pr_tags() {
    local pr_url=$1
    local pr_tags

    pr_tags=$(curl -s "$pr_url/labels" -H "Authorization: Basic $AUTH" | jq -c '.value[].name')
    HOURS=$(grep -iPo "$KUP_PATTERN" <<< "$pr_tags" | head -n1 | xargs)

    print_debug
    print_debug "PR_TAGS = $pr_tags"
    print_debug "PR tags HOURS = $HOURS"

    if [ -n "$HOURS" ]; then
        print_info "Hours found in PR Tags"
    fi
}

function check_pr_commits() {
    local pr_url=$1
    local commits_response
    local commits
    local commit_comment=""
    local commit_id=""
    local pr_hours=0
    local commit_hours=0

    commits_response=$(curl -s "$pr_url/commits" -H "Authorization: Basic $AUTH")
    commits=$(jq -c '.value[] | { id: .commitId, comment: .comment }' <<< "$commits_response")

    print_debug
    print_debug "List of commits in PR:"
    print_debug "$commits"
    print_debug

    if [ -z "$commits" ]; then
        print_error "No commits discovered"
    else
        IFS=$'\n'

        for commit in $commits; do
            print_debug "Commit = $commit"

            commit_id=$(jq -r '.id' <<< "$commit")
            commit_comment=$(jq -r '.comment' <<< "$commit")

            print_debug
            print_debug "COMMIT_ID = $commit_id"
            print_debug "COMMIT_COMMENT = $commit_comment"
            print_debug

            # ignore known commit, because we already counted it
            if [ -n "${KNOWN_COMMITS[${commit_id}]}" ]; then
                if [[ "$DEBUG" == 1 ]]; then
                    print_warning "[IGNORE]\t$commit_id: $commit_comment as KNOWN"
                fi

                continue
            fi

            print_debug "[INCLUDE]\t$commit_id: $commit_comment"
            KNOWN_COMMITS[$commit_id]=$commit_comment # add commit to knowns to avoid multiple participation

            commit_hours=$(grep -iPo "$KUP_PATTERN" <<< "$commit_comment" | head -n1 | xargs)

            if [ -n "$commit_hours" ]; then
                pr_hours=$((pr_hours + commit_hours))
            fi

        done

        unset IFS;
    fi

    if [ $pr_hours -gt 0 ]; then
        HOURS=$pr_hours
        print_info "Hours found in PR Commits"
    fi
}

function append_pr_line() {
    local pr=$1
    local line_number=$2
    local hours_cell="{\small $HOURS}"
    local pr_href_text
    local pr_href_url
    local pr_title
    local pr_id
    local pr_full_date
    local pr_date
    local workitem_api_url
    local workitem
    local workitem_href_text
    local workitem_href_url
    local workitem_title
    local workitem_cell
    local owner_name=""

    # get info about PR and try read KUP from title or description
    pr_href_text=$(jq -r '"PR \(.id)" ' <<< "$pr")
    pr_href_url=$(jq -r '.url | sub("_apis/git/repositories"; "_git") | sub("/pullRequests/"; "/pullRequest/")' <<< "$pr")
    pr_title=$(jq -r '.title' <<< "$pr" | sed -e 's|[#$%&_{}~]|\\&|g')
    local pr_cell="{\small \href{$pr_href_url}{$pr_href_text}: $pr_title}"

    # get info about workitem
    pr_id=$(jq -r '.id' <<< "$pr")
    workitem_api_url=$(az repos pr work-item list --id "$pr_id" --query '[0].url' -o tsv)

    print_debug "WORKITEM_API_URL = $workitem_api_url"

    if [ -n "$workitem_api_url" ]; then
        # get work title from workitem
        workitem=$(curl -s "$workitem_api_url?fields=System.Title,System.WorkItemType,System.Id,Custom.Owner" -H "Authorization: Basic $AUTH")
        workitem_href_text=$(jq -r '"\(.fields["System.WorkItemType"]) \(.fields["System.Id"])"' <<< "$workitem")
        workitem_href_url=$(jq -r '._links.html.href' <<< "$workitem")
        workitem_title=$(jq -r '.fields["System.Title"]' <<< "$workitem" | sed -e 's|[#$%&_{}~]|\\&|g')
        workitem_cell="{\small \href{$workitem_href_url}{$workitem_href_text}: $workitem_title}"

        # get userstory owner
        owner_email=$(jq -r '.fields["Custom.Owner"].uniqueName // empty' <<< "$workitem")
        owner_name=$(jq -r '.fields["Custom.Owner"].displayName // empty' <<< "$workitem")
    else
        workitem_cell="{\small $pr_title}"
    fi

    # set manager as OWNER in case when we cannot find owner
    if [ -z "$owner_email" ]; then
        owner_email=$MANAGER_EMAIL
        owner_name=$MANAGER_DISPLAY
    fi

    local owner_cell="{\small \href{mailto:$owner_email}{$owner_name}}"

    print_debug "OWNER_EMAIL = $owner_email"
    print_debug "OWNER_NAME = $owner_name"
    print_debug "OWNER_CELL = $owner_cell"

    # PR created date
    pr_full_date=$(jq -r '.closedDate' <<< "$pr")
    pr_date=$(date -d "$pr_full_date" +%Y-%m-%d)
    local pr_date_cell="{\small $pr_date}"

    echo "$line_number & $workitem_cell & $pr_cell & $hours_cell & $pr_date_cell & $owner_cell \\\\" >> _lines.txt
    echo "\hline" >> _lines.txt
}

PROJECTS=$(az devops project list | jq -r '.value[].name')
while read -r project; do
    print_text # empty line
    print_text "Searching project $project..."

    PULL_REQUESTS=$(az repos pr list -p "$project" --status completed --creator "$AUTHOR_ID" \
    --query '[?closedDate > `'"$START_DATE"'`].{title: title, description: description, id: pullRequestId, url: url, closedDate: closedDate}' | jq -rc 'sort_by(.closedDate) | .[]' -)

    if [ -z "$PULL_REQUESTS" ]; then
        print_error "No Pull requests found in this project, moving next..."
        continue
    fi

    while read -r pr; do 
        PR_URL=$(jq -r '.url' <<< "$pr")

        print_warning # empty line
        print_warning "$(jq -r '"\(.id) \(.title)"' <<< "$pr")"

        print_debug
        print_debug "URL = $PR_URL"
        print_debug "PR = $pr"

        # check PR title
        check_pr_title "$pr"

        # check PR description
        if [ -z "$HOURS" ]; then
            check_pr_description "$pr"
        fi

        # check PR tags
        if [ -z "$HOURS" ]; then
            check_pr_tags "$PR_URL"
        fi

        # check PR commits
        if [ -z "$HOURS" ]; then
            check_pr_commits "$PR_URL"
        fi

        # skip PR if no hours found
        if [ -z "$HOURS" ]; then
            print_error "KUP has not been found, skip this PR"
            continue
        fi

        print_success "HOURS: $HOURS"

        # building result file only in normal mode (not silent)
        if [[ $SILENT -ne 1 ]]; then
            append_pr_line "$pr" $LINE_NUMBER
        fi

        # Increase TOTAL_HOURS
        TOTAL_HOURS=$((TOTAL_HOURS + HOURS))

        # Increase line LINE_NUMBER
        LINE_NUMBER=$((LINE_NUMBER + 1))
    done <<< "$PULL_REQUESTS"

done <<< "$PROJECTS"

# Calculate percentage using integer arithmetic
TOTAL_EXPECTED_HOURS=$((PARAM_DAYS * 8))
# Use integer percentage (rounded)
PERCENTAGE=$((TOTAL_HOURS * 100 / TOTAL_EXPECTED_HOURS))

print_success
print_success "PRs have been collected!"

# Compare using integer percentage values
if (( PERCENTAGE < 25 )); then
    print_error "Total hours for this month: $TOTAL_HOURS of $TOTAL_EXPECTED_HOURS ($PERCENTAGE%)"
elif (( PERCENTAGE < 50 )); then
    print_warning "Total hours for this month: $TOTAL_HOURS of $TOTAL_EXPECTED_HOURS ($PERCENTAGE%)"
elif (( PERCENTAGE > 70 )); then
    print_error "TOO MUCH!!! Total hours for this month: $TOTAL_HOURS of $TOTAL_EXPECTED_HOURS ($PERCENTAGE%)"
else
    print_success "Total hours for this month: $TOTAL_HOURS of $TOTAL_EXPECTED_HOURS ($PERCENTAGE%)"
fi

# stop program if we are in silent mode
if [[ $SILENT -eq 1 ]]; then
    exit 0
fi

print_text

MONTH_TEMPLATE_FILE="$AUTHOR_DISPLAY, $(date +%Y-%m).tex"
cp -f "kup_report_template.tex" "$(pwd)/out/$MONTH_TEMPLATE_FILE"
print_text "Report template copied to $(pwd)/out/$MONTH_TEMPLATE_FILE"

# replace ==PLACEHOLDERS== with their values
sed -i \
    -e "s|==AUTHOR==|$AUTHOR_DISPLAY|" \
    -e "s|==AUTHOR_TITLE==|$AUTHOR_TITLE|" \
    -e "s|==MANAGER==|$MANAGER_DISPLAY|" \
    -e "s|==MANAGER_TITLE==|$MANAGER_TITLE|" \
    -e "s|==MONTH==|$PARAM_MONTH|" \
    -e "s|==DAYS==|$PARAM_DAYS|" \
    -e "s|==ABS==|$PARAM_ABS|" \
    -e "/==LINES==/{r _lines.txt
    d}" \
    "./out/$MONTH_TEMPLATE_FILE"

if [[ "$DEBUG" == 1 ]]; then
    # Run pdf creation
    pdflatex -interaction=batchmode -output-directory=./out "./out/$MONTH_TEMPLATE_FILE"
else
    # Run pdf creation
    pdflatex -interaction=batchmode -output-directory=./out "./out/$MONTH_TEMPLATE_FILE" > /dev/null 2>&1

    # remove everything except PDF
    find ./out/ -maxdepth 1 -type f ! -name '*.pdf' -exec rm -f {} +
fi
