#!/bin/bash
set -o pipefail

# constants
ECHO_RED='\033[0;31m'
ECHO_GREEN='\033[0;32m'
ECHO_YELLOW='\033[0;33m'
ECHO_CYAN='\033[0;36m' 
ECHO_GREY='\033[0;90m' 
ECHO_NC='\033[0m' # No Color

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

function print_text() {
    if [[ "$SILENT" == 0 ]]; then
        echo -e "$1"
    fi
}

# environment variables
if [ -z "$AUTHOR_EMAIL" ]; then
    echo -e "${ECHO_RED}Environment variable AUTHOR_EMAIL is not set${ECHO_NC}"
    exit 1
fi

if [ -z "$MANAGER_EMAIL" ]; then
    echo -e "${ECHO_RED}Environment variable MANAGER_EMAIL is not set${ECHO_NC}"
    exit 1
fi

if [ -z "$AZURE_DEVOPS_EXT_PAT" ]; then
    echo -e "${ECHO_RED}Environment variable AZURE_DEVOPS_EXT_PAT is not set${ECHO_NC}"
    exit 1
fi

if [ ! -d ./out ]; then
    echo -e "${ECHO_RED}Please mount output volume '{host_dir}:$(pwd)/out:rw'${ECHO_NC}"
    exit 1
fi

#variables
AUTH=$(echo -n "$AUTHOR_EMAIL:$AZURE_DEVOPS_EXT_PAT" | base64 -w 0)

if [[ "$DEBUG" == 1 ]]; then
    echo -e "${ECHO_GREY}DEBUG: AZURE_DEVOPS_EXT_PAT = $AZURE_DEVOPS_EXT_PAT${ECHO_NC}"
    echo -e "${ECHO_GREY}DEBUG: AUTH = $AUTH${ECHO_NC}"
fi

TOTAL_HOURS="0"
LINE_NUMBER="1"
KUP_PATTERN='(?<=\[KUP:)\s*\d+([\.,]\d+)?(?=\])'
declare -A KNOWN_COMMITS

# reading input parameters
PARAM_LINES=""
PARAM_MONTH=$(date -d $START_DATE +%B)
PARAM_DAYS=$(sed -n "$(date +%m)p" calendar.txt | cut -f2 -d '|')

if [[ "$SILENT" == 0 ]]; then 
    if [ -z "$PARAM_DAYS" ]; then
        echo -n 'Working days in the Period: '
        read PARAM_DAYS
    else
        print_text "Working days in the Period: $PARAM_DAYS"
    fi

    if [ -z "$PARAM_ABS" ]; then
        echo -n 'Authors days of absence: '
        read PARAM_ABS
    fi
fi 

rm -f "_lines.txt"

# get author id and print_text name

AUTHOR=$(az devops user list --top 500 | jq '.members[] | select(.user.mailAddress | ascii_downcase == ("'$AUTHOR_EMAIL'" | ascii_downcase))' -)
AUTHOR_ID=$(jq -r '.id' <<< $AUTHOR)
AUTHOR_DISPLAY=$(jq -r '.user.displayName' <<< $AUTHOR)

if [ -z "$AUTHOR" ]; then
    echo -e "${ECHO_RED}Cannot find author by email $AUTHOR_EMAIL, your PAT is not valid or user is not exist${ECHO_NC}"
    exit 1
fi

MANAGER=$(az devops user list --top 500 | jq '.members[] | select(.user.mailAddress | ascii_downcase == ("'$MANAGER_EMAIL'" | ascii_downcase))' -)
MANAGER_DISPLAY=$(jq -r '.user.displayName' <<< $MANAGER)

if [ -z "$MANAGER" ]; then
    echo -e "${ECHO_RED}Cannot find manager by email $MANAGER_EMAIL, your PAT is not valid or user is not exist${ECHO_NC}"
    exit 1
fi

print_text
print_text "AUTHOR: $AUTHOR_DISPLAY"
print_text "AUTHOR_TITLE: $AUTHOR_TITLE"
print_text "MANAGER: $MANAGER_DISPLAY"
print_text "MANAGER_TITLE: $MANAGER_TITLE"
print_text

print_text "Searching PRs from $START_DATE..."

PROJECTS=$(az devops project list | jq -r '.value[].name')
while read project; do
    print_text # empty line
    print_text "Searching project $project..."

    PULL_REQUESTS=$(az repos pr list -p "$project" --status completed --creator $AUTHOR_ID \
    --query '[?closedDate > `'$START_DATE'`].{title: title, description: description, id: pullRequestId, url: url, closedDate: closedDate}' | jq -rc 'sort_by(.closedDate) | .[]' -)

    if [ -z "$PULL_REQUESTS" ]; then
        print_text "${ECHO_RED}No Pull requests found in this project, moving next...${ECHO_NC}"
        continue
    fi

    while read -r pr; do 
        PR_URL=$(jq -r '.url' <<< $pr)
        print_text # empty line
        print_text "${ECHO_CYAN}$(jq -r '"\(.id) \(.title)"' <<< $pr)${ECHO_NC}"

        if [[ "$DEBUG" == 1 ]]; then
            print_text
            print_text "${ECHO_GREY}DEBUG: URL = $PR_URL${ECHO_NC}"
            print_text "${ECHO_GREY}DEBUG: PR = $pr${ECHO_NC}"
        fi

        PR_TITLE=$(jq -r '.title' <<< $pr)
        HOURS=$(grep -iPo -m 1 $KUP_PATTERN <<< $PR_TITLE | head -n1 | xargs)

        if [[ "$DEBUG" == 1 ]]; then
            print_text
            print_text "${ECHO_GREY}DEBUG: PR title HOURS = [$HOURS]${ECHO_NC}"
        fi

        if [ ! -z "$HOURS" ]; then
            print_text "${ECHO_YELLOW}Hours found in PR Title${ECHO_NC}"
        fi

        if [ -z "$HOURS" ]; then
            PR_DESCRIPTION=$(jq -r '.description' <<< $pr)
            HOURS=$(grep -iPo $KUP_PATTERN <<< $PR_DESCRIPTION | head -n1 | xargs)

            if [[ "$DEBUG" == 1 ]]; then
                print_text
                print_text "${ECHO_GREY}DEBUG: PR description HOURS = [$HOURS]${ECHO_NC}"
            fi

            if [ ! -z "$HOURS" ]; then
                print_text "${ECHO_YELLOW}Hours found in PR Description${ECHO_NC}"
            fi
        fi

        if [ -z "$HOURS" ]; then
            PR_TAGS=$(curl -s "$PR_URL/labels" -H "Authorization: Basic $AUTH" | jq -c '.value[].name')
            HOURS=$(grep -iPo $KUP_PATTERN <<< $PR_TAGS | head -n1 | xargs)

            if [[ "$DEBUG" == 1 ]]; then
                print_text
                print_text "${ECHO_GREY}DEBUG: PR_TAGS = $PR_TAGS${ECHO_NC}"
                print_text "${ECHO_GREY}DEBUG: PR tags HOURS = $HOURS${ECHO_NC}"
            fi

            if [ ! -z "$HOURS" ]; then
                print_text "${ECHO_YELLOW}Hours found in PR Tags${ECHO_NC}"
            fi
        fi

        PR_COMMITS_RESPONSE=$(curl -s "$PR_URL/commits" -H "Authorization: Basic $AUTH")
        PR_COMMITS=$(jq -c '.value[] | { id: .commitId, comment: .comment }' <<< $PR_COMMITS_RESPONSE)
        PR_COMMITS_HOURS="0"

        if [[ $DEBUG == 1 ]]; then
            print_text
            print_text "${ECHO_GREY}DEBUG: List of commits in PR:${ECHO_NC}"
            print_text "${ECHO_GREY}$PR_COMMITS${ECHO_NC}"
            print_text
        fi 

        if [ -z "$PR_COMMITS" ]; then
            print_text "${ECHO_RED}No commits discovered${ECHO_NC}"
        else
            IFS=$'\n'

            for commit in $PR_COMMITS; do
                if [[ "$DEBUG" == 1 ]]; then
                    print_text "${ECHO_GREY}DEBUG: Commit = $commit${ECHO_NC}"
                fi

                COMMIT_ID=$(jq -r '.id' <<< $commit)
                COMMIT_COMMENT=$(jq -r '.comment' <<< $commit)

                if [[ "$DEBUG" == 1 ]]; then
                    print_text
                    print_text "${ECHO_GREY}DEBUG: COMMIT_ID = $COMMIT_ID${ECHO_NC}"
                    print_text "${ECHO_GREY}DEBUG: COMMIT_COMMENT = $COMMIT_COMMENT${ECHO_NC}"
                    print_text
                fi

                if [ ! -z "${KNOWN_COMMITS[${COMMIT_ID}]}" ]; then
                    if [[ "$DEBUG" == 1 ]]; then
                        print_text "${ECHO_YELLOW}[IGNORE]\t$COMMIT_ID: $COMMIT_COMMENT as KNOWN${ECHO_NC}"
                    fi

                    continue
                fi

                if [[ "$DEBUG" == 1 ]]; then
                    print_text "${ECHO_GREY}[INCLUDE]\t$COMMIT_ID: $COMMIT_COMMENT${ECHO_NC}"
                fi

                KNOWN_COMMITS[$COMMIT_ID]=$COMMIT_COMMENT # add commit to knowns to avoid multiple participations
                # echo "Commit added to KNOWN $COMMIT_ID: $COMMIT_COMMENT"

                if [ -z "$HOURS" ]; then
                    HOURS=$(grep -iPo $KUP_PATTERN <<< $COMMIT_COMMENT | head -n1 | xargs)

                    if [ ! -z "$HOURS" ]; then
                        PR_COMMITS_HOURS=$(echo "$PR_COMMITS_HOURS + $HOURS" | bc)
                    fi

                    HOURS=""
                fi
            done

            unset IFS;
        fi

        if [ -z "$HOURS" ]; then
            if [ "$PR_COMMITS_HOURS" == "0" ]; then
                print_text "${ECHO_RED}KUP has not been found, skip this PR${ECHO_NC}"
                continue
            fi

            HOURS=$PR_COMMITS_HOURS

            if [ ! -z "$HOURS" ]; then
                print_text "${ECHO_YELLOW}Hours found in PR Commits${ECHO_NC}"
            fi
        fi

        print_text "${ECHO_GREEN}HOURS: $HOURS${ECHO_NC}"
        HOURS_CELL="{\small $HOURS}"

        # get info about PR and try read KUP from title or description
        PR_HREF_TEXT=$(jq -r '"PR \(.id)" ' <<< $pr)
        PR_HREF_URL=$(jq -r '.url | sub("_apis/git/repositories"; "_git") | sub("/pullRequests/"; "/pullRequest/")' <<< $pr)
        PR_TITLE=$(jq -r '.title' <<< $pr | sed -e 's|[#$%&_{}~]|\\&|g')
        PR_CELL="{\small \href{$PR_HREF_URL}{$PR_HREF_TEXT}: $PR_TITLE}"
        # echo "PR_CELL: $PR_CELL"

        # get info about workitem
        PR_ID=$(jq -r '.id' <<< $pr)
        WORKITEM_API_URL=$(az repos pr work-item list --id $PR_ID --query '[0].url' -o tsv)

        if [[ $DEBUG == 1 ]]; then
            print_text "${ECHO_GREY}DEBUG: WORKITEM_API_URL = $WORKITEM_API_URL"
        fi

        if [ ! -z $WORKITEM_API_URL ]; then
            # get work title from workitem
            WORKITEM=$(curl -s "$WORKITEM_API_URL?fields=System.Title,System.WorkItemType,System.Id,Custom.Owner" -H "Authorization: Basic $AUTH")
            WORKITEM_HREF_TEXT=$(jq -r '"\(.fields["System.WorkItemType"]) \(.fields["System.Id"])"' <<< $WORKITEM)
            WORKITEM_HREF_URL=$(jq -r '._links.html.href' <<< $WORKITEM)
            WORKITEM_TITLE=$(jq -r '.fields["System.Title"]' <<< $WORKITEM | sed -e 's|[#$%&_{}~]|\\&|g')
            WORKITEM_CELL="{\small \href{$WORKITEM_HREF_URL}{$WORKITEM_HREF_TEXT}: $WORKITEM_TITLE}"

            # get userstory owner
            OWNER_EMAIL=$(jq -r '.fields["Custom.Owner"].uniqueName // empty' <<< $WORKITEM)
            OWNER_NAME=$(jq -r '.fields["Custom.Owner"].displayName // empty' <<< $WORKITEM)
        else
            WORKITEM_CELL="{\small $PR_TITLE}"
            OWNER_EMAIL=''
            OWNER_NAME=''
        fi

        if [[ $DEBUG == 1 ]]; then 
            print_text "${ECHO_GREY}DEBUG: OWNER_EMAIL = $OWNER_EMAIL${ECHO_NC}"
            print_text "${ECHO_GREY}DEBUG: OWNER_NAME = $OWNER_NAME${ECHO_NC}"
        fi

        if [ ! -z "$OWNER_EMAIL" ]; then
            OWNER_CELL="{\small \href{mailto:$OWNER_EMAIL}{$OWNER_NAME}}"
        else
            OWNER_CELL="{\small \href{mailto:$MANAGER_EMAIL}{$MANAGER_DISPLAY}}"
        fi

        if [[ $DEBUG == 1 ]]; then 
            print_text "${ECHO_GREY}DEBUG: OWNER_CELL = $OWNER_CELL${ECHO_NC}"
        fi

        # PR created date
        PR_FULL_DATE=$(jq -r '.closedDate' <<< $pr)
        PR_DATE=$(date -d $PR_FULL_DATE +%Y-%m-%d)
        PR_DATE_CELL="{\small $PR_DATE}"
        # echo "PR_DATE_CELL: $PR_DATE_CELL"

        if [[ $SILENT -ne 1 ]]; then
            # collecting all table lines in separate file to easy replace in pdf template
            echo "$LINE_NUMBER & $WORKITEM_CELL & $PR_CELL & $HOURS_CELL & $PR_DATE_CELL & $OWNER_CELL \\\\" >> _lines.txt
            echo "\hline" >> _lines.txt
        fi

        # Increase TOTAL_HOURS
        TOTAL_HOURS=$(echo "$TOTAL_HOURS + $HOURS" | bc)
        # Increase line LINE_NUMBER
        LINE_NUMBER=$((LINE_NUMBER + 1))
    done <<< $PULL_REQUESTS
done <<< $PROJECTS

PERCENTAGE=$(echo "scale=2; $TOTAL_HOURS / ($PARAM_DAYS * 8) * 100" | bc)

echo
echo "PRs have been collected!"
if (( $(echo "$PERCENTAGE < 25" | bc -l) )); then
    echo -e "${ECHO_RED}Total hours for this month: $TOTAL_HOURS of $(echo "$PARAM_DAYS * 8" | bc) ($PERCENTAGE%)${ECHO_NC}"
elif (( $(echo "$PERCENTAGE < 50" | bc -l) )); then
    echo -e "${ECHO_YELLOW}Total hours for this month: $TOTAL_HOURS of $(echo "$PARAM_DAYS * 8" | bc) ($PERCENTAGE%)${ECHO_NC}"
else
    echo -e "${ECHO_GREEN}Total hours for this month: $TOTAL_HOURS of $(echo "$PARAM_DAYS * 8" | bc) ($PERCENTAGE%)${ECHO_NC}"
fi
echo

# stop program if we are in silent mode
if [[ $SILENT -eq 1 ]]; then
    exit 0
fi

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