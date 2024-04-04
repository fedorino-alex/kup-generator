#!/bin/bash

AUTHOR='Aliaksandr Fedaryna'
AUTHOR_ID='8bcc898b-e56e-48f5-be3c-d94c3ab67c1c'
AUTHOR_EMAIL='aliaksandr.fedaryna@ihsmarkit.com'
PAT=''
AUTH=$(echo -n "$AUTHOR_EMAIL:$PAT" | base64 -w 0)
TOTAL_HOURS="0"
NUMBER="1"

KUP_PATTERN='(?<=\[KUP:)\d+([\.,]\d+)?(?=\])'

# START_DATE='2024-03-01T00:00:00.000000+00:00'
START_DATE=$(date +%Y-%m-01T00:00:00.000000+00:00)

# reading input parameters
PARAM_MONTH=$(date -d $START_DATE +%B)
echo -n 'Working days in the Period: '
read PARAM_DAYS
echo -n 'Authors days of absence: '
read PARAM_ABS
PARAM_LINES=""

rm -f "_lines.txt"

echo "Searching PRs from $START_DATE..."

PULL_REQUESTS=$(az repos pr list -p EWB --status completed --creator $AUTHOR_ID \
--query '[?closedDate > `'$START_DATE'`].{title: title, description: description, id: pullRequestId, url: url, closedDate: closedDate}' | jq -rc .[] -)

while read pr; do 
    # echo "Pull Request line: $pr"

    # get KUP hours from PR (title, description and list of commits are searchable)
    HOURS=$(grep -iPo $KUP_PATTERN <<< $pr)
    if [ -z "$HOURS" ]; then
        echo "PR does not contain any KUP information, checking all commits..."

        PR_COMMITS_URL=$(jq -r '.url' <<< $pr)
        PR_COMMITS=$(curl -s "$PR_COMMITS_URL/commits" -H "Authorization: Basic $AUTH" | jq -rc '.value[].comment')
        PR_COMMITS_HOURS="0"

        while read commit; do
            # echo "$commit"

            HOURS=$(grep -iPo $KUP_PATTERN <<< $commit)
            if [ ! -z "$HOURS" ]; then
                PR_COMMITS_HOURS=$(echo "$PR_COMMITS_HOURS + $HOURS" | bc)
                # echo "PR_COMMITS_HOURS: $PR_COMMITS_HOURS"
            fi
        done <<< $PR_COMMITS

        # echo "PR_COMMITS_HOURS: $PR_COMMITS_HOURS"
        if [ "$PR_COMMITS_HOURS" == "0" ]; then
            echo "Nothing find in commits, skip this PR"
            continue
        fi

        $HOURS=$PR_COMMITS_HOURS
    fi

    HOURS_CELL="{\small $HOURS}"
    # echo "HOURS_CELL: $HOURS_CELL"

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

echo "PRs have been collected"

MONTH_TEMPLATE_FILE="$(date +%Y-%m).tex"
cp -f "kup_report_template.tex" "$MONTH_TEMPLATE_FILE"

echo "Report template copied to $MONTH_TEMPLATE_FILE"

# replace ==PLACEHOLDERS== with their values
sed -i \
    -e "s/==MONTH==/$PARAM_MONTH/" \
    -e "s/==DAYS==/$PARAM_DAYS/" \
    -e "s/==ABS==/$PARAM_ABS/" \
    -e "/==LINES==/{r _lines.txt
    d}" \
    $MONTH_TEMPLATE_FILE

# Run pdf creation
pdflatex -interaction=batchmode $MONTH_TEMPLATE_FILE

rm -f $MONTH_TEMPLATE_FILE _lines.txt