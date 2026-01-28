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

    if [ -z "$AZURE_DEVOPS_ORG" ]; then
        print_error "Environment variable AZURE_DEVOPS_ORG is not set"
        return 1
    fi

    if [ -z "$AZURE_DEVOPS_EXT_PAT" ]; then
        print_error "Environment variable AZURE_DEVOPS_EXT_PAT is not set"
        return 1
    fi

    return 0
}

function check_github_pr_title() {
    local pr=$1
    local kup_pattern=$2
    local title
    local title_hours

    title=$(echo "$pr" | jq -r '.title')
    title_hours=$(grep -iPo -m 1 "$kup_pattern" <<< "$title" | head -n1 | xargs)

    if [ -n "$title_hours" ]; then
        HOURS=$title_hours
        print_success "Found $HOURS hours in PR Title"

        return
    fi

    print_debug # empty line
    print_debug "Hours were not found in PR Title"
}

function check_github_pr_body() {
    local pr=$1
    local kup_pattern=$2
    local body
    local hours_body

    body=$(echo "$pr" | jq -r '.body // ""')
    hours_body=$(grep -iPo -m 1 "$kup_pattern" <<< "$body" | head -n1 | xargs)

    if [ -n "$hours_body" ]; then
        print_success "Found $hours_body hours in PR Body"
        HOURS=$hours_body

        return
    fi

    print_debug # empty line
    print_debug "Hours were not found in PR Body"
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

    print_debug "PR = $pr"

    # get info about PR
    pr_number=$(echo "$pr" | jq -r '.number')
    pr_href_text="PR $pr_number"
    pr_href_url=$(echo "$pr" | jq -r '.html_url')
    pr_title=$(echo "$pr" | jq -r '.title' | sed -e 's|[#$%&_{}~]|\\&|g')
    pr_body=$(echo "$pr" | jq -r '.body // ""')
    local pr_cell="{\small \href{$pr_href_url}{$pr_href_text}: $pr_title}"

    # Extract Azure DevOps workitem reference from PR body or title
    # Patterns: [AB#12345](https://dev.azure.com/pdd-ihsmarkit/.../_workitems/edit/12345) 

    print_debug "PR Body = $pr_body"

    workitem_id=$(echo -e "$pr_body" | grep -iPo "(?<=\[AB#)(\d*)(?=\]\(https\:\/\/dev\.azure\.com\/$AZURE_DEVOPS_ORG\/.*\/\_workitems\/edit\/\1\))" | uniq | head -n1 || echo "<NONE>")

    print_debug "WORKITEM_ID extracted: $workitem_id"

    if [ -n "$workitem_id" ] && [ "$workitem_id" != "<NONE>" ] && [ -n "$AZURE_DEVOPS_ORG" ] && [ -n "$AZURE_DEVOPS_EXT_PAT" ]; then
        # Try to get full workitem information from Azure DevOps
        local workitem_api_url="https://dev.azure.com/$AZURE_DEVOPS_ORG/_apis/wit/workitems/$workitem_id"
        print_debug "Fetching workitem from: $workitem_api_url"

        # Use the shared function from azure-devops.sh
        local workitem_info=$(get_azure_workitem_info "$workitem_api_url" "$AZURE_DEVOPS_AUTH")
        print_debug "WORKITEM_INFO = $workitem_info"

        if [ -n "$(echo "$workitem_info" | jq -r '.href_text')" ]; then
            # Successfully got workitem info from Azure DevOps
            local wi_href_text
            local wi_href_url
            local wi_title
            
            wi_href_text=$(echo "$workitem_info" | jq -r '.href_text')
            wi_href_url=$(echo "$workitem_info" | jq -r '.href_url')
            wi_title=$(echo "$workitem_info" | jq -r '.title' | sed -e 's|[#$%&_{}~]|\\&|g')

            workitem_cell="{\small \href{$wi_href_url}{$wi_href_text}: $wi_title}"

            # Get owner from workitem if available
            local wi_owner_email=$(echo "$workitem_info" | jq -r '.owner_email')
            local wi_owner_name=$(echo "$workitem_info" | jq -r '.owner_name')

            if [ -n "$wi_owner_email" ] && [ "$wi_owner_email" != "null" ]; then
                owner_email="$wi_owner_email"
                owner_name="$wi_owner_name"
            fi
        else
            # Fallback: just create a link to the workitem ID
            local workitem_url="https://dev.azure.com/$AZURE_DEVOPS_ORG/_workitems/edit/$workitem_id"
            workitem_cell="{\small \href{$workitem_url}{WorkItem $workitem_id}: $pr_title}"
        fi
    else
        print_warning "No valid workitem reference found in PR body or title"

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

    # PR merged date
    pr_date=$(echo "$pr" | jq -r '.closed_at' | cut -d'T' -f1)
    local pr_date_cell="{\small $pr_date}"

    print_debug "LINE_NUMBER = $line_number"
    print_debug "WORKITEM_CELL = $workitem_cell"
    print_debug "PR_CELL = $pr_cell"
    print_debug "HOURS_CELL = $hours_cell"
    print_debug "PR_DATE_CELL = $pr_date_cell"
    print_debug "OWNER_CELL = $owner_cell"

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

    local search_results
    local search_results_count
    local formatted_date

    local total_hours="0.0"     # result

    # Fast check: search for user's PRs across the org
    print_text "Fast check, Looking for users activity in $github_org..."
    print_text

    # Convert start_date to ISO format for GitHub search (YYYY-MM-DD)
    formatted_date=$(date -d "$start_date" +%Y-%m-%d 2>/dev/null || echo "$start_date" | cut -d'T' -f1)

    print_debug "GitHub Org: $github_org"
    print_debug "Formatted Date: $formatted_date"
    print_debug "Search Query: org:$github_org+type:pr+author:@me+is:merged+merged:>=$formatted_date"

    # Search for merged PRs by author across the org
    # GitHub PRs are searched via /search/issues endpoint with type:pr filter
    search_results=$(curl -sS -H "Authorization: token $github_token" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/search/issues?q=org:$github_org+type:pr+author:@me+is:merged+merged:>=$formatted_date" 2>&1)
    
    # Check for API errors - GitHub returns status code and message in JSON on errors
    local http_code=$(echo "$search_results" | jq -r '.status // "200"')
    local api_message=$(echo "$search_results" | jq -r '.message // empty')
    local api_error_detail=$(echo "$search_results" | jq -r '.errors[0].message // empty')
    
    print_debug "HTTP Status Code: $http_code"
    print_debug "API Message: $api_message"
    print_debug "API Error Detail: $api_error_detail"
    
    # Use detailed error message if available, otherwise use top-level message
    if [ -n "$api_error_detail" ]; then
        api_message="$api_error_detail"
    fi

    # Check if there's an error (non-200 status or error message present)
    if [ "$http_code" != "200" ] || [ -n "$api_message" ]; then
        print_error "GitHub API Error (HTTP $http_code): $api_message"
        print_error ""
        
        # Specific error handling based on status code and message content
        if [[ "$api_message" == *"Bad credentials"* ]] || [ "$http_code" == "401" ]; then
            print_error "❌ Token authentication failed:"
            print_error "   - Your GitHub token is invalid or expired"
            print_error "   - Create a new token at: https://github.com/settings/tokens"
            print_error "   - Update GITHUB_TOKEN in your docker-compose.yaml"
            
        elif [[ "$api_message" == *"cannot be searched"* ]] || [[ "$api_message" == *"do not have permission"* ]] || [ "$http_code" == "422" ]; then
            print_error "❌ Organization access denied:"
            print_error "   This usually means your token needs SSO authorization."
            print_error ""
            print_error "   To fix this:"
            print_error "   1. Go to https://github.com/settings/tokens"
            print_error "   2. Find your token and click 'Configure SSO'"
            print_error "   3. Click 'Authorize' for organization: $github_org"
            print_error ""
            print_error "   Other possible causes:"
            print_error "   - Organization name is incorrect (current: $github_org)"
            print_error "   - You don't have access to this organization"
            print_error "   - Token lacks required scopes (repo, read:org)"
            
        elif [[ "$api_message" == *"rate limit"* ]] || [ "$http_code" == "403" ]; then
            print_error "❌ Rate limit or permission issue:"
            print_error "   - GitHub API rate limit may be exceeded"
            print_error "   - Token may lack required scopes (repo, read:org)"
            print_error "   - SSO authorization may be required for organization: $github_org"
            print_error ""
            print_error "   Check rate limit: https://api.github.com/rate_limit"
            print_error "   Configure SSO: https://github.com/settings/tokens"
            
        elif [ "$http_code" == "404" ]; then
            print_error "❌ Not Found (404):"
            print_error "   - Organization '$github_org' may not exist"
            print_error "   - You may not have access to this organization"
            print_error "   - Verify the organization name is correct"
            
        else
            print_error "❌ Unexpected error"
            print_error "   Please check your token permissions and organization access"
        fi
        
        print_error ""
        print_warning "Skipping GitHub collection due to API error"
        echo "$total_hours"
        return 0
    fi

    search_results_count=$(echo "$search_results" | jq -r '.total_count // 0')

    if [ "$search_results_count" == "0" ]; then
        print_warning "No merged PRs found for $author_email in organization $github_org since $formatted_date"
        print_warning "Skipping GitHub collection"

        echo "$total_hours"
        return 0
    fi

    print_success "Found $search_results_count merged PR(s) for $author_email since $formatted_date"

    # GitHub Search API returns max 100 items per page, max 1000 total
    local per_page=100
    local max_pages=$(( 1 + (search_results_count - 1) / per_page ))

    # GitHub Search API limits to 1000 results (10 pages of 100)
    if [ $max_pages -gt 10 ]; then
        print_warning "More than 1000 PRs found. GitHub Search API limits results to 1000. Consider narrowing date range."
        max_pages=10
    fi

    # Iterate through pages
    for ((page=1; page<=max_pages; page++)); do
        print_text "Fetching page $page/$max_pages..."

        # Get page results
        local page_results=$(curl -sS -H "Authorization: token $github_token" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/search/issues?q=org:$github_org+type:pr+author:@me+is:merged+merged:>=$formatted_date&per_page=$per_page&page=$page" 2>&1)
        
        # Check for HTTP status in JSON response
        local page_http_code=$(echo "$page_results" | jq -r '.status // "200"')
        
        print_debug "Page $page HTTP Status: $page_http_code"
        
        # Check HTTP status for pagination
        if [ "$page_http_code" != "200" ]; then
            print_error "HTTP Error $page_http_code on page $page"
            
            if [ "$page_http_code" == "403" ]; then
                print_warning "Rate limit or permission issue. Stopping collection."
                break
            else
                print_warning "Skipping page $page due to HTTP error"
                continue
            fi
        fi

        # Check for API errors in pagination JSON
        local page_error=$(echo "$page_results" | jq -r '.message // empty')
        if [ -n "$page_error" ]; then
            print_error "GitHub API Error on page $page: $page_error"
            
            if [[ "$page_error" == *"rate limit"* ]]; then
                print_warning "Rate limit reached. Stopping collection."
                break
            else
                print_warning "Skipping page $page due to error"
                continue
            fi
        fi

        local prs=$(echo "$page_results" | jq -c '.items[]')

        if [ -z "$prs" ]; then
            print_warning "No PRs found on page $page"
            continue
        fi
        
        while read -r pr; do
            [ -z "$pr" ] && continue
            
            # Get PR details from search result
            local pr_number=$(echo "$pr" | jq -r '.number')
            local pr_title=$(echo "$pr" | jq -r '.title')
            local pr_url=$(echo "$pr" | jq -r '.pull_request.url')
            local repo_url=$(echo "$pr" | jq -r '.repository_url')
            local repo=$(echo "$repo_url" | sed 's|https://api.github.com/repos/||')

            print_info # empty line
            print_info "Processing: [$repo] #$pr_number $pr_title"

            HOURS=""

            # check PR title
            check_github_pr_title "$pr" "$kup_pattern"

            # check PR body
            if [ -z "$HOURS" ]; then
                check_github_pr_body "$pr" "$kup_pattern"
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
        done <<< "$prs"
    done

    echo "$total_hours"
}
