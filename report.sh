#!/bin/bash

# constants
ECHO_RED='\033[0;31m'
ECHO_GREEN='\033[0;32m'
ECHO_YELLOW='\033[0;33m'
ECHO_CYAN='\033[0;36m' 
ECHO_NC='\033[0m' # No Color

# test values 
PARAM_DAYS="0"
PARAM_ABS="0"

# START_DATE='2024-03-01T00:00:00.000000+00:00'
START_DATE=$(date +%Y-%m-01T00:00:00.000000+00:00)

# environment variables
AUTHOR_EMAIL='aliaksandr.fedaryna@accuristech.com'
if [ -z $AUTHOR_EMAIL ]; then
    echo -e "${ECHO_RED}Environment variable AUTHOR_EMAIL is not set${ECHO_NC}"
    exit 1
fi

AZURE_DEVOPS_EXT_PAT=$(grep -iPo '(?<=personal access token = ).+(?=$)' ~/.azure/azuredevops/personalAccessTokens)
if [ -z $AZURE_DEVOPS_EXT_PAT ]; then
    echo -e "${ECHO_RED}Environment variable AZURE_DEVOPS_EXT_PAT is not set${ECHO_NC}"
    exit 1
fi 

if [ ! -d ./out ]; then
    echo -e "${ECHO_RED}Please mount output volume '{host_dir}:$(pwd)/out:rw'${ECHO_NC}"
    exit 1
fi

#variables
PROJECTS=(EWB PLC)
AUTH=$(echo -n "$AUTHOR_EMAIL:$AZURE_DEVOPS_EXT_PAT" | base64 -w 0)
TOTAL_HOURS="0"
NUMBER="1"
KUP_PATTERN='(?<=\[KUP:)\d+([\.,]\d+)?(?=\])'
declare -A KNOWN_COMMITS

# reading input parameters
PARAM_LINES=""
PARAM_MONTH=$(date -d $START_DATE +%B)

if [ -z $PARAM_DAYS ]; then
    echo -n 'Working days in the Period: '
    read PARAM_DAYS
fi

if [ -z $PARAM_ABS ]; then
    echo -n 'Authors days of absence: '
    read PARAM_ABS
fi

# get author id and display name
AUTHOR=$(az devops user list --query 'members[?user.mailAddress == `'$AUTHOR_EMAIL'`]' | jq '.[0]' -)
AUTHOR_ID=$(jq -r '.id' <<< $AUTHOR)
AUTHOR_DISPLAY=$(jq -r '.user.displayName' <<< $AUTHOR)

rm -f "_lines.txt"

echo "Searching PRs from $START_DATE..."

for project in ${PROJECTS[@]}
do
    echo # empty line
    echo "Searching project $project..."

    PULL_REQUESTS=$(az repos pr list -p $project --status completed --creator $AUTHOR_ID \
    --query '[?closedDate > `'$START_DATE'`].{title: title, description: description, id: pullRequestId, url: url, closedDate: closedDate}' | jq -rc 'sort_by(.closedDate) | .[]' -)

    while read pr; do 
        echo # empty line
        echo -e "${ECHO_CYAN}$(jq -r '"\(.id) \(.title)"' <<< $pr)${ECHO_NC}"

        # get KUP hours from PR (title, description and list of commits are searchable)
        HOURS=$(grep -iPo $KUP_PATTERN <<< $pr)
        # echo -e "${ECHO_RED}DEBUG${ECHO_NC}: HOURS=$HOURS"

        if [ -z "$HOURS" ]; then
            echo "PR does not contain any KUP information, checking all commits..."
        fi

        PR_COMMITS_URL=$(jq -r '.url' <<< $pr)
        PR_COMMITS=$(curl -s "$PR_COMMITS_URL/commits" -H "Authorization: Basic $AUTH" | jq -c '.value[] | {id: .commitId, comment: .comment}')
        PR_COMMITS_HOURS="0"

        if [ -z "$PR_COMMITS" ]; then
            echo -e "${ECHO_RED}No commits discovered${ECHO_NC}"
        else
            while read commit; do
                COMMIT_ID=$(jq -r '.id' <<< $commit)
                COMMIT_COMMENT=$(jq -r '.comment' <<< $commit)

                if [ ! -z "${KNOWN_COMMITS[${COMMIT_ID}]}" ]; then
                    echo -e "${ECHO_YELLOW}Skip commit $COMMIT_ID: $COMMIT_COMMENT as KNOWN${ECHO_NC}"
                    continue
                fi

                echo -e "${ECHO_GREEN}$COMMIT_ID: $COMMIT_COMMENT${ECHO_NC}"

                KNOWN_COMMITS[$COMMIT_ID]=$COMMIT_COMMENT # add commit to knowns to avoid multiple participations
                # echo "Commit added to KNOWN $COMMIT_ID: $COMMIT_COMMENT"

                if [ -z "$HOURS" ]; then
                    HOURS=$(grep -iPo $KUP_PATTERN <<< $COMMIT_COMMENT)

                    if [ ! -z "$HOURS" ]; then
                        PR_COMMITS_HOURS=$(echo "$PR_COMMITS_HOURS + $HOURS" | bc)
                    fi

                    HOURS=""
                fi
            done <<< $PR_COMMITS
        fi

        if [ -z "$HOURS" ]; then
            if [ "$PR_COMMITS_HOURS" == "0" ]; then
                echo -e "${ECHO_RED}Nothing find in commits, skip this PR${ECHO_NC}"
                continue
            fi

            HOURS=$PR_COMMITS_HOURS
        fi

        echo "HOURS: $HOURS"
        HOURS_CELL="{\small $HOURS}"

        # get info about PR and try read KUP from title or description
        PR_HREF_TEXT=$(jq -r '"PR \(.id)" ' <<< $pr)
        PR_HREF_URL=$(jq -r '.url | sub("_apis/git/repositories"; "_git") | sub("/pullRequests/"; "/pullRequest/")' <<< $pr)
        PR_TITLE=$(jq -r '.title' <<< $pr)
        PR_CELL="{\small \href{$PR_HREF_URL}{$PR_HREF_TEXT}: $PR_TITLE}"
        # echo "PR_CELL: $PR_CELL"

        # get info about workitem
        PR_ID=$(jq -r '.id' <<< $pr)
        WORKITEM_API_URL=$(az repos pr work-item list --id $PR_ID --query '[0].url' -o tsv)
        WORKITEM=$(curl -s "$WORKITEM_API_URL?fields=System.Title,System.WorkItemType,System.Id,Custom.Owner" -H "Authorization: Basic $AUTH")

        WORKITEM_HREF_TEXT=$(jq -r '"\(.fields["System.WorkItemType"]) \(.fields["System.Id"])"' <<< $WORKITEM)
        WORKITEM_HREF_URL=$(jq -r '._links.html.href' <<< $WORKITEM)
        WORKITEM_TITLE=$(jq -r '.fields["System.Title"]' <<< $WORKITEM)
        WORKITEM_CELL="{\small \href{$WORKITEM_HREF_URL}{$WORKITEM_HREF_TEXT}: $WORKITEM_TITLE}"
        # echo "WORKITEM_CELL: $WORKITEM_CELL"

        # get userstory owner
        OWNER_EMAIL=$(jq -r '.fields["Custom.Owner"].uniqueName' <<< $WORKITEM)
        OWNER_NAME=$(jq -r '.fields["Custom.Owner"].displayName' <<< $WORKITEM)
        if [ ! -z "$OWNER_EMAIL" ]; then
            OWNER_CELL="{\small \href{mailto:$OWNER_EMAIL}{$OWNER_NAME}}"
        else
            # TODO: check this with bugs and put QA here
            OWNER_CELL="{\small \href{mailto:$AUTHOR_EMAIL}{$AUTHOR}}"
        fi

        # PR created date
        PR_FULL_DATE=$(jq -r '.closedDate' <<< $pr)
        PR_DATE=$(date -d $PR_FULL_DATE +%Y-%m-%d)
        PR_DATE_CELL="{\small $PR_DATE}"
        # echo "PR_DATE_CELL: $PR_DATE_CELL"

        # collecting all table lines in separate file to easy replace in pdf template
        echo "$NUMBER & $PR_CELL & $WORKITEM_CELL & $HOURS_CELL & $PR_DATE_CELL & $OWNER_CELL \\\\" >> _lines.txt
        echo "\hline" >> _lines.txt

        # Increase TOTAL_HOURS
        TOTAL_HOURS=$(echo "$TOTAL_HOURS + $HOURS" | bc)
        # Increase line number
        NUMBER=$((NUMBER + 1))
    done <<< $PULL_REQUESTS
done

echo
echo "PRs have been collected"

MONTH_TEMPLATE_FILE="$(date +%Y-%m).tex"
cp -f "kup_report_template.tex" "$(pwd)/out/$MONTH_TEMPLATE_FILE"

echo "Report template copied to $(pwd)/out/$MONTH_TEMPLATE_FILE"

# replace ==PLACEHOLDERS== with their values
sed -i \
    -e "s/==MONTH==/$PARAM_MONTH/" \
    -e "s/==DAYS==/$PARAM_DAYS/" \
    -e "s/==ABS==/$PARAM_ABS/" \
    -e "/==LINES==/{r _lines.txt
    d}" \
    ./out/$MONTH_TEMPLATE_FILE

# Run pdf creation
pdflatex -interaction=batchmode -output-directory=./out ./out/$MONTH_TEMPLATE_FILE > /dev/null 2>&1

# remove everything except PDF
find ./out/ -maxdepth 1 -type f ! -name '*.pdf' -exec rm -f {} +
