#!/bin/bash
# GitHub specific functions

function validate_github_env() {
    if [ -z "$GITHUB_TOKEN" ]; then
        print_error "Environment variable GITHUB_TOKEN is not set"
        return 1
    fi
    
    if [ -z "$GITHUB_ORG" ]; then
        print_error "Environment variable GITHUB_ORG is not set"
        return 1
    fi
    return 0
}

function get_github_author() {
    local author_email=$1
    local github_token=$2
    
    # For GitHub, we'll use the email directly and get display name from PRs
    # GitHub API doesn't have a simple user list like Azure DevOps
    echo "$author_email"
}

function check_github_pr_title() {
    local pr=$1
    local kup_pattern=$2
    local title

    title=$(echo "$pr" | jq -r '.title')
    HOURS=$(grep -iPo -m 1 "$kup_pattern" <<< "$title" | head -n1 | xargs)

    print_debug # empty line
    print_debug "PR title HOURS = [$HOURS]" 

    if [ -n "$HOURS" ]; then
        print_success "Found $HOURS hours in PR Title"
    fi
}

function check_github_pr_body() {
    local pr=$1
    local kup_pattern=$2
    local body

    body=$(echo "$pr" | jq -r '.body // ""')
    HOURS=$(grep -iPo -m 1 "$kup_pattern" <<< "$body" | head -n1 | xargs)

    print_debug # empty line
    print_debug "PR body HOURS = [$HOURS]" 

    if [ -n "$HOURS" ]; then
        print_success "Found $HOURS hours in PR Body"
    fi
}

function check_github_pr_labels() {
    local pr=$1
    local kup_pattern=$2
    local pr_labels

    pr_labels=$(echo "$pr" | jq -c '.labels[].name')
    HOURS=$(grep -iPo "$kup_pattern" <<< "$pr_labels" | head -n1 | xargs)

    print_debug
    print_debug "PR_LABELS = $pr_labels"
    print_debug "PR labels HOURS = $HOURS"

    if [ -n "$HOURS" ]; then
        print_success "Found $HOURS hours in PR Labels"
    fi
}

function check_github_pr_commits() {
    local repo=$1
    local pr_number=$2
    local kup_pattern=$3
    local github_token=$4
    local commits_response
    local commits
    local commit_message=""
    local commit_sha=""
    local pr_hours=0.0
    local commit_hours=0

    commits_response=$(curl -s -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$repo/pulls/$pr_number/commits")
    
    commits=$(echo "$commits_response" | jq -c '.[] | { sha: .sha, message: .commit.message }')

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

            commit_sha=$(echo "$commit" | jq -r '.sha')
            commit_message=$(echo "$commit" | jq -r '.message')

            print_debug
            print_debug "COMMIT_SHA = $commit_sha"
            print_debug "COMMIT_MESSAGE = $commit_message"
            print_debug

            # ignore known commit, because we already counted it
            if [ -n "${KNOWN_COMMITS[${commit_sha}]}" ]; then
                if [[ "$DEBUG" == 1 ]]; then
                    print_warning "[IGNORE]\t$commit_sha: $commit_message as KNOWN"
                fi

                continue
            fi

            print_debug "[INCLUDE]\t$commit_sha: $commit_message"
            KNOWN_COMMITS[$commit_sha]=$commit_message # add commit to knowns to avoid multiple participation

            commit_hours=$(grep -iPo "$kup_pattern" <<< "$commit_message" | head -n1 | xargs)

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

function append_github_pr_line() {
    local pr=$1
    local line_number=$2
    local hours=$3
    local repo=$4
    local manager_email=$5
    local manager_display=$6
    local github_token=$7
    local hours_cell="{\small $hours}"
    local pr_href_text
    local pr_href_url
    local pr_title
    local pr_number
    local pr_date
    local pr_body
    local owner_name=""
    local owner_email=""
    local workitem_id=""
    local workitem_cell=""

    # get info about PR
    pr_number=$(echo "$pr" | jq -r '.number')
    pr_href_text="PR $pr_number"
    pr_href_url=$(echo "$pr" | jq -r '.html_url')
    pr_title=$(echo "$pr" | jq -r '.title' | sed -e 's|[#$%&_{}~]|\\&|g')
    pr_body=$(echo "$pr" | jq -r '.body // ""')
    local pr_cell="{\small \href{$pr_href_url}{$pr_href_text}: $pr_title}"

    # Extract Azure DevOps workitem reference from PR body or title
    # Patterns: AB#12345, #12345, or full URLs
    
    workitem_id=$(echo -e "$pr_body" | grep -iPo "(?<=\[AB#)(\d*)(?=\]\(https\:\/\/dev\.azure\.com\/$AZURE_DEVOPS_ORG\/.*\/\_workitems\/edit\/\1\))" | uniq | head -n1 || echo "<NONE>")
    
    print_debug "WORKITEM_ID extracted: $workitem_id"

    if [ -n "$workitem_id" ] && [ -n "$AZURE_DEVOPS_ORG" ] && [ -n "$AZURE_DEVOPS_EXT_PAT" ]; then
        # Try to get full workitem information from Azure DevOps
        local auth
        auth=$(echo -n ":$AZURE_DEVOPS_EXT_PAT" | base64 -w 0)
        local workitem_api_url="https://dev.azure.com/$AZURE_DEVOPS_ORG/_apis/wit/workitems/$workitem_id"

        print_debug "Fetching workitem from: $workitem_api_url"
        
        # Use the shared function from azure-devops.sh
        local workitem_info
        workitem_info=$(get_azure_workitem_info "$workitem_api_url" "$auth")
        
        if [ "$(echo "$workitem_info" | jq -r '.href_text')" != "null" ] && [ -n "$(echo "$workitem_info" | jq -r '.href_text')" ]; then
            # Successfully got workitem info from Azure DevOps
            local wi_href_text
            local wi_href_url
            local wi_title
            
            wi_href_text=$(echo "$workitem_info" | jq -r '.href_text')
            wi_href_url=$(echo "$workitem_info" | jq -r '.href_url')
            wi_title=$(echo "$workitem_info" | jq -r '.title' | sed -e 's|[#$%&_{}~]|\\&|g')
            
            workitem_cell="{\small \href{$wi_href_url}{$wi_href_text}: $wi_title}"
            
            # Get owner from workitem if available
            local wi_owner_email
            local wi_owner_name
            wi_owner_email=$(echo "$workitem_info" | jq -r '.owner_email')
            wi_owner_name=$(echo "$workitem_info" | jq -r '.owner_name')
            
            if [ -n "$wi_owner_email" ] && [ "$wi_owner_email" != "null" ]; then
                owner_email="$wi_owner_email"
                owner_name="$wi_owner_name"
            fi
        else
            # Fallback: just create a link to the workitem ID
            local workitem_url="https://dev.azure.com/$AZURE_DEVOPS_ORG/_workitems/edit/$workitem_id"
            workitem_cell="{\small \href{$workitem_url}{WorkItem $workitem_id}: $pr_title}"
        fi
    elif [ -n "$workitem_id" ]; then
        # Workitem ID found but no Azure DevOps access configured
        workitem_cell="{\small WorkItem $workitem_id: $pr_title}"
    else
        # No workitem found, use PR title as workitem
        workitem_cell="{\small $pr_title}"
    fi

    # Get PR author as owner
    owner_name=$(echo "$pr" | jq -r '.user.login')
    owner_email=$(echo "$pr" | jq -r '.user.email // ""')
    
    # set manager as OWNER in case when we cannot find owner
    if [ -z "$owner_email" ]; then
        owner_email=$manager_email
        owner_name=$manager_display
    fi

    local owner_cell="{\small \href{mailto:$owner_email}{$owner_name}}"

    print_debug "OWNER_EMAIL = $owner_email"
    print_debug "OWNER_NAME = $owner_name"
    print_debug "OWNER_CELL = $owner_cell"

    # PR merged date
    pr_date=$(echo "$pr" | jq -r '.merged_at' | cut -d'T' -f1)
    local pr_date_cell="{\small $pr_date}"

    echo "$line_number & $workitem_cell & $pr_cell & $hours_cell & $pr_date_cell & $owner_cell \\\\" >> _lines.txt
    echo "\hline" >> _lines.txt
}

function collect_github_prs() {
    local author_email=$1
    local start_date=$2
    local kup_pattern=$3
    local github_token=$4
    local github_org=$5
    local manager_email=$6
    local manager_display=$7
    local line_number=$8
    local total_hours="0.0"

    # Fast check: search for user's PRs across the org
    print_text "Fast check: Looking for user's activity in $github_org..."
    
    local user_search
    local formatted_date
    # Convert start_date to ISO format for GitHub search (YYYY-MM-DD)
    formatted_date=$(date -d "$start_date" +%Y-%m-%d 2>/dev/null || echo "$start_date" | cut -d'T' -f1)
    
    # Search for merged PRs by author across the org
    # GitHub PRs are searched via /search/issues endpoint with type:pr filter
    user_search=$(curl -s -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/search/issues?q=org:$github_org+type:pr+author:$author_email+is:merged+merged:>=$formatted_date" | \
        jq -r '.total_count // 0')
    
    print_debug "PR search result: $user_search"
    
    if [ "$user_search" == "0" ]; then
        print_warning "No merged PRs found for $author_email in organization $github_org since $formatted_date"
        print_warning "Skipping GitHub collection"
        echo "0.0"
        return 0
    fi
    
    print_success "Found $user_search merged PR(s) for $author_email since $formatted_date"
    
    # Get all repositories in the organization
    print_text "Fetching repositories from organization $github_org..."
    
    REPOS=$(curl -s -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$github_org/repos?per_page=100" | jq -r '.[].full_name')

    while read -r repo; do
        [ -z "$repo" ] && continue
        
        print_text # empty line
        print_text "Searching repository $repo..."

        # Get merged PRs created by the author since start_date
        PULL_REQUESTS=$(curl -s -H "Authorization: token $github_token" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$repo/pulls?state=closed&per_page=100" | \
            jq -c --arg email "$author_email" --arg date "$start_date" \
            '.[] | select(.user.email == $email or .user.login == $email) | select(.merged_at != null) | select(.merged_at >= $date)')

        if [ -z "$PULL_REQUESTS" ]; then
            print_warning "No Pull requests found in this repository, moving next..."
            continue
        fi

        while read -r pr; do
            [ -z "$pr" ] && continue
            
            PR_NUMBER=$(echo "$pr" | jq -r '.number')
            PR_TITLE=$(echo "$pr" | jq -r '.title')

            print_info # empty line
            print_info "$PR_NUMBER $PR_TITLE"

            print_debug
            print_debug "PR = $pr"

            HOURS=""

            # check PR title
            check_github_pr_title "$pr" "$kup_pattern"

            # check PR body
            if [ -z "$HOURS" ]; then
                check_github_pr_body "$pr" "$kup_pattern"
            fi

            # check PR labels
            if [ -z "$HOURS" ]; then
                check_github_pr_labels "$pr" "$kup_pattern"
            fi

            # check PR commits
            if [ -z "$HOURS" ]; then
                check_github_pr_commits "$repo" "$PR_NUMBER" "$kup_pattern" "$github_token"
            fi

            # skip PR if no hours found
            if [ -z "$HOURS" ]; then
                print_warning "KUP has not been found, skip this PR"
                continue
            fi

            # building result file only in normal mode (not silent)
            if (( SILENT == 0 )); then
                append_github_pr_line "$pr" $line_number "$HOURS" "$repo" "$manager_email" "$manager_display" "$github_token"
            fi

            # Increase TOTAL_HOURS
            total_hours=$(awk "BEGIN {printf \"%.2f\", $total_hours + $HOURS}")

            # Increase line LINE_NUMBER
            line_number=$((line_number + 1))
        done <<< "$PULL_REQUESTS"

    done <<< "$REPOS"

    echo "$total_hours"
}
