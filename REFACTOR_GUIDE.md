# KUP Report Generator - Refactored Structure

## Overview

The report generator has been refactored to support multiple sources (Azure DevOps and GitHub/GitHub Enterprise).

## File Structure

```
.
├── report.sh                 # Legacy monolithic script (kept for backward compatibility)
├── report-new.sh            # New refactored main script
└── lib/
    ├── common.sh            # Common utilities and functions
    ├── azure-devops.sh      # Azure DevOps specific functions
    └── github.sh            # GitHub/GitHub Enterprise specific functions
```

## Usage

### Both Sources (default)

Collects PRs from both Azure DevOps and GitHub in a single run:

```bash
export AUTHOR_EMAIL="your.email@example.com"
export MANAGER_EMAIL="manager.email@example.com"

# Azure DevOps credentials
export AZURE_DEVOPS_EXT_PAT="your-azure-pat-token"

# GitHub credentials
export GITHUB_TOKEN="your-github-token"
export GITHUB_ORG="your-org-name"

# Optional display names
export AUTHOR_NAME="Your Display Name"
export MANAGER_NAME="Manager Name"

# Titles
export AUTHOR_TITLE="Your Title"
export MANAGER_TITLE="Manager Title"

./report-new.sh
# or explicitly
./report-new.sh --source both
```

### Azure DevOps Only

```bash
export AUTHOR_EMAIL="your.email@example.com"
export MANAGER_EMAIL="manager.email@example.com"
export AZURE_DEVOPS_EXT_PAT="your-azure-pat-token"
export AUTHOR_TITLE="Your Title"
export MANAGER_TITLE="Manager Title"

./report-new.sh --source azure
```

### GitHub / GitHub Enterprise Only

```bash
export AUTHOR_EMAIL="your.email@example.com"
export MANAGER_EMAIL="manager.email@example.com"
export GITHUB_TOKEN="your-github-token"
export GITHUB_ORG="your-org-name"
export AZURE_DEVOPS_EXT_PAT="your-azure-pat-token"
export AUTHOR_TITLE="Your Title"
export MANAGER_TITLE="Manager Title"

./report-new.sh --source github
```

### Options

- `--mode debug|silent` - Set execution mode
  - `debug`: Show detailed debug information
  - `silent`: Suppress output (for automated runs)
  
- `--source azure|github|both` - Select the source platform(s)
  - `azure`: Azure DevOps only
  - `github`: GitHub or GitHub Enterprise only
  - `both`: Both sources in a single run (default)

## Environment Variables

### Common (Required for both sources)

- `AUTHOR_EMAIL` - Email of the PR author
- `MANAGER_EMAIL` - Email of the manager
- `AUTHOR_TITLE` - Job title of the author
- `MANAGER_TITLE` - Job title of the manager

### Azure DevOps Specific

- `AZURE_DEVOPS_EXT_PAT` - Personal Access Token for Azure DevOps

### GitHub Specific

- `GITHUB_TOKEN` - Personal Access Token for GitHub
- `GITHUB_ORG` - GitHub organization name
- `AUTHOR_NAME` - Display name for author (optional)
- `MANAGER_NAME` - Display name for manager (optional)

### Optional (for GitHub + Azure DevOps Integration)

- `AZURE_DEVOPS_ORG` - Azure DevOps organization name (for workitem linking from GitHub PRs)
- `AZURE_DEVOPS_EXT_PAT` - Azure DevOps PAT (for fetching workitem details from GitHub PRs)

## KUP Time Tracking Format

The system looks for time entries in the following format: `[KUP: X.X]` where X.X is hours.

Example: `[KUP: 2.5]` for 2.5 hours

The system searches for KUP entries in:
1. PR Title
2. PR Description/Body
3. PR Labels/Tags
4. Commit messages

## Library Modules

### common.sh

Contains shared utilities:
- Print functions (error, info, warning, debug, success, text)
- PDF report generation
- Summary statistics calculation
- Output directory validation

### azure-devops.sh

Azure DevOps specific functions:
- Environment validation
- Author/Manager lookup
- PR collection and parsing
- Work item integration
- Commit analysis

### github.sh

GitHub specific functions:
- Environment validation
- Repository enumeration
- PR collection via GitHub API
- Label and commit analysis
- GitHub Enterprise support

## Migration from Legacy Script

The legacy `report.sh` is preserved for backward compatibility. To migrate:

1. Test the new script: `./report-new.sh`
2. Once validated, replace the old script: `mv report-new.sh report.sh`

## Adding New Sources

To add support for a new platform:

1. Create `lib/new-platform.sh`
2. Implement required functions:
   - `validate_<platform>_env()`
   - `get_<platform>_author()`
   - `collect_<platform>_prs()`
3. Source the new library in `report-new.sh`
4. Add source option handling
