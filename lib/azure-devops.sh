#!/bin/bash
# Azure DevOps specific functions

function validate_azure_devops_env() {
    if [ -z "$AZURE_DEVOPS_EXT_PAT" ]; then
        print_error "Environment variable AZURE_DEVOPS_EXT_PAT is not set"
        return 1
    fi
    return 0
}

function get_azure_devops_author() {
    local author_email=$1
    
    AUTHOR=$(az devops user list --top 500 | jq '.members[] | select(.user.mailAddress | ascii_downcase == ("'"$author_email"'" | ascii_downcase))' -)
    AUTHOR_ID=$(jq -r '.id' <<< "$AUTHOR")
    AUTHOR_DISPLAY=$(jq -r '.user.displayName' <<< "$AUTHOR")

    if [ -z "$AUTHOR" ]; then
        print_error "Cannot find author by email $author_email, your PAT is not valid or user does not exist"
        exit 1
    fi

    echo "$AUTHOR"
}

function get_azure_devops_manager() {
    local manager_email=$1
    
    MANAGER=$(az devops user list --top 500 | jq '.members[] | select(.user.mailAddress | ascii_downcase == ("'"$manager_email"'" | ascii_downcase))' -)
    MANAGER_DISPLAY=$(jq -r '.user.displayName' <<< "$MANAGER")

    if [ -z "$MANAGER" ]; then
        print_error "Cannot find manager by email $manager_email, your PAT is not valid or user does not exist"
        exit 1
    fi

    echo "$MANAGER"
}

function check_azure_pr_title() {
    local pr=$1
    local kup_pattern=$2
    local title

    title=$(jq -r '.title' <<< "$pr")
    HOURS=$(grep -iPo -m 1 "$kup_pattern" <<< "$title" | head -n1 | xargs)

    print_debug # empty line
    print_debug "PR title HOURS = [$HOURS]" 

    if [ -n "$HOURS" ]; then
        print_success "Found $HOURS hours in PR Title"
    fi
}

function check_azure_pr_description() {
    local pr=$1
    local kup_pattern=$2
    local description

    description=$(jq -r '.description' <<< "$pr")
    HOURS=$(grep -iPo -m 1 "$kup_pattern" <<< "$description" | head -n1 | xargs)

    print_debug # empty line
    print_debug "PR description HOURS = [$HOURS]" 

    if [ -n "$HOURS" ]; then
        print_success "Found $HOURS hours in PR Description"
    fi
}

function check_azure_pr_tags() {
    local pr_url=$1
    local kup_pattern=$2
    local auth=$3
    local pr_tags

    pr_tags=$(curl -s "$pr_url/labels" -H "Authorization: Basic $auth" | jq -c '.value[].name')
    HOURS=$(grep -iPo "$kup_pattern" <<< "$pr_tags" | head -n1 | xargs)

    print_debug
    print_debug "PR_TAGS = $pr_tags"
    print_debug "PR tags HOURS = $HOURS"

    if [ -n "$HOURS" ]; then
        print_success "Found $HOURS hours in PR Tags"
    fi
}

function check_azure_pr_commits() {
    local pr_url=$1
    local kup_pattern=$2
    local auth=$3
    local commits_response
    local commits
    local commit_comment=""
    local commit_id=""
    local pr_hours=0.0
    local commit_hours=0

    commits_response=$(curl -s "$pr_url/commits" -H "Authorization: Basic $auth")
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

            commit_hours=$(grep -iPo "$kup_pattern" <<< "$commit_comment" | head -n1 | xargs)

            if [ -n "$commit_hours" ]; then
                pr_hours=$(awk "BEGIN {printf \"%.2f\", $pr_hours + $commit_hours}")
            fi

        done

        unset IFS;
    fi

    if (( $(awk "BEGIN {print ($pr_hours > 0)}") )); then
        HOURS=$pr_hours
        print_success "Found $HOURS hours in PR Commits"
    fi
}

function append_azure_pr_line() {
    local pr=$1
    local line_number=$2
    local hours=$3
    local auth=$4
    local manager_email=$5
    local manager_display=$6
    local hours_cell="{\small $hours}"
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

    if [ -n "$workitem_api_url" ] && [ "$workitem_api_url" != "null" ]; then
        # Get workitem information using shared function
        local workitem_info
        workitem_info=$(get_azure_workitem_info "$workitem_api_url" "$auth")
        
        workitem_href_text=$(echo "$workitem_info" | jq -r '.href_text')
        workitem_href_url=$(echo "$workitem_info" | jq -r '.href_url')
        workitem_title=$(echo "$workitem_info" | jq -r '.title' | sed -e 's|[#$%&_{}~]|\\&|g')
        workitem_cell="{\small \href{$workitem_href_url}{$workitem_href_text}: $workitem_title}"

        # Get userstory owner
        owner_email=$(echo "$workitem_info" | jq -r '.owner_email')
        owner_name=$(echo "$workitem_info" | jq -r '.owner_name')
    else
        workitem_cell="{\small $pr_title}"
    fi

    # set manager as OWNER in case when we cannot find owner
    if [ -z "$owner_email" ]; then
        owner_email=$manager_email
        owner_name=$manager_display
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

function collect_azure_devops_prs() {
    local author_id=$1
    local start_date=$2
    local kup_pattern=$3
    local auth=$4
    local manager_email=$5
    local manager_display=$6
    local line_number=$7
    local total_hours="0.0"

    # Fast check: get total PR count across all projects
    print_text "Fast check: Looking for user's PRs since $start_date..."
    
    local total_pr_count=0
    PROJECTS=$(az devops project list | jq -r '.value[].name')
    
    # Quick scan for any PRs
    while read -r project; do
        [ -z "$project" ] && continue
        local pr_count=$(az repos pr list -p "$project" --status completed --creator "$author_id" \
            --query "[?closedDate > \`$start_date\`] | length(@)" -o tsv 2>/dev/null || echo "0")
        total_pr_count=$((total_pr_count + pr_count))
    done <<< "$PROJECTS"
    
    if [ "$total_pr_count" == "0" ]; then
        print_warning "No completed PRs found for author ID $author_id since $start_date"
        print_warning "Skipping Azure DevOps collection"
        echo "0.0"
        return 0
    fi
    
    print_success "Found $total_pr_count completed PR(s) since $start_date"
    
    # Now collect detailed information
    PROJECTS=$(az devops project list | jq -r '.value[].name')
    while read -r project; do
        print_text # empty line
        print_text "Searching project $project..."

        PULL_REQUESTS=$(az repos pr list -p "$project" --status completed --creator "$author_id" \
        --query '[?closedDate > `'"$start_date"'`].{title: title, description: description, id: pullRequestId, url: url, closedDate: closedDate}' | jq -rc 'sort_by(.closedDate) | .[]' -)

        if [ -z "$PULL_REQUESTS" ]; then
            print_warning "No Pull requests found in this project, moving next..."
            continue
        fi

        while read -r pr; do 
            PR_URL=$(jq -r '.url' <<< "$pr")

            print_info # empty line
            print_info "$(jq -r '"\(.id) \(.title)"' <<< "$pr")"

            print_debug
            print_debug "URL = $PR_URL"
            print_debug "PR = $pr"

            HOURS=""

            # check PR title
            check_azure_pr_title "$pr" "$kup_pattern"

            # check PR description
            if [ -z "$HOURS" ]; then
                check_azure_pr_description "$pr" "$kup_pattern"
            fi

            # check PR tags
            if [ -z "$HOURS" ]; then
                check_azure_pr_tags "$PR_URL" "$kup_pattern" "$auth"
            fi

            # check PR commits
            if [ -z "$HOURS" ]; then
                check_azure_pr_commits "$PR_URL" "$kup_pattern" "$auth"
            fi

            # skip PR if no hours found
            if [ -z "$HOURS" ]; then
                print_warning "KUP has not been found, skip this PR"
                continue
            fi

            # building result file only in normal mode (not silent)
            if (( SILENT == 0 )); then
                append_azure_pr_line "$pr" $line_number "$HOURS" "$auth" "$manager_email" "$manager_display"
            fi

            # Increase TOTAL_HOURS
            total_hours=$(awk "BEGIN {printf \"%.2f\", $total_hours + $HOURS}")

            # Increase line LINE_NUMBER
            line_number=$((line_number + 1))
        done <<< "$PULL_REQUESTS"

    done <<< "$PROJECTS"

    echo "$total_hours"
}

function get_azure_workitem_info() {
    local workitem_api_url=$1
    local auth=$2
    local workitem_json=""
    local workitem_href_text=""
    local workitem_href_url=""
    local workitem_title=""
    local owner_email=""
    local owner_name=""
    
    if [ -z "$workitem_api_url" ] || [ "$workitem_api_url" == "null" ]; then
        echo "{}"
        return 0
    fi
    
    # Get work item details from workitem API
    workitem_json=$(curl -s "$workitem_api_url?fields=System.Title,System.WorkItemType,System.Id,Custom.Owner" -H "Authorization: Basic $auth")
    
    workitem_href_text=$(jq -r '"\(.fields["System.WorkItemType"]) \(.fields["System.Id"])"' <<< "$workitem_json")
    workitem_href_url=$(jq -r '._links.html.href' <<< "$workitem_json")
    workitem_title=$(jq -r '.fields["System.Title"]' <<< "$workitem_json")
    owner_email=$(jq -r '.fields["Custom.Owner"].uniqueName // empty' <<< "$workitem_json")
    owner_name=$(jq -r '.fields["Custom.Owner"].displayName // empty' <<< "$workitem_json")
    
    # Return as JSON string for easy parsing
    jq -n \
        --arg href_text "$workitem_href_text" \
        --arg href_url "$workitem_href_url" \
        --arg title "$workitem_title" \
        --arg owner_email "$owner_email" \
        --arg owner_name "$owner_name" \
        '{
            href_text: $href_text,
            href_url: $href_url,
            title: $title,
            owner_email: $owner_email,
            owner_name: $owner_name
        }'
}
