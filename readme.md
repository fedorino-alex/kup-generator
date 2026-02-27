# KUP Report Generator

[![Semantic Release](https://img.shields.io/badge/semantic--release-enabled-brightgreen?logo=semantic-release)](https://github.com/semantic-release/semantic-release)
[![Docker Image](https://img.shields.io/docker/v/fedorinoalex/kup-generator?logo=docker&label=docker)](https://hub.docker.com/r/fedorinoalex/kup-generator)

Collects pull requests from **Azure DevOps** and/or **GitHub** for the current month and generates a PDF report according to the provided LaTeX template. Tracks only PRs where `[KUP:<hours>]` text is found in **title**, **description**, **tags**, or **commit messages**.

## Features

- 🔄 **Multi-source support**: Collect PRs from Azure DevOps, GitHub, or both
- 📊 **Floating-point hours**: Supports decimal hours (e.g., `[KUP:4.5]`)
- 🔍 **Smart commit tracking**: Prevents duplicate counting of commits across PRs
- 📄 **PDF generation**: Automatically creates professional LaTeX reports
- 🎯 **Flexible configuration**: Choose which sources to use via command-line options
- 📈 **Work statistics**: Displays utilization percentages and warns about anomalies

## Contributing

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automatic semantic versioning. Please see [CONTRIBUTING.md](CONTRIBUTING.md) for commit message format and contribution guidelines.

## Quick Start with Docker

### Pull and Run

```bash
docker pull fedorinoalex/kup-generator:latest
docker run --rm -v ./out:/kup/out \
  -e AZURE_DEVOPS_EXT_PAT="your_azure_token" \
  -e AZURE_DEVOPS_ORG="your_azure_org" \
  -e GITHUB_TOKEN="your_github_token" \
  -e GITHUB_ORG="your_org" \
  -e AUTHOR_EMAIL="your.email@company.com" \
  -e AUTHOR_TITLE="Your Title" \
  -e MANAGER_EMAIL="manager@company.com" \
  -e MANAGER_TITLE="Manager Title" \
  fedorinoalex/kup-generator:latest
```

### Using Docker Compose

1. **Update `docker-compose.yaml` environment variables:**

```yaml
environment:
  # Common settings (required)
  - AUTHOR_EMAIL=your.email@company.com
  - AUTHOR_TITLE=Your Job Title
  - MANAGER_EMAIL=manager@company.com
  - MANAGER_TITLE=Manager Job Title
  
  # Azure DevOps (optional - required if using Azure source)
  - AZURE_DEVOPS_EXT_PAT=your_azure_devops_pat
  - AZURE_DEVOPS_ORG=your_azure_devops_org
  
  # GitHub (optional - required if using GitHub source)
  - GITHUB_TOKEN=your_github_token
  - GITHUB_ORG=your_organization_name
```

2. **Mount output volume:**
   - The `./out` folder must be mounted to `/kup/out` for storing PDF reports

3. **Run:**

```bash
# Pull latest image
docker-compose pull

# Run with both sources (default)
docker-compose run --rm kup

# Run with specific source
docker-compose run --rm kup --source azure
docker-compose run --rm kup --source github
```

## Command-Line Options

### `--mode <debug|silent>`

Controls output verbosity:
- `debug`: Enables detailed logging for troubleshooting
- `silent`: Suppresses all output (useful for automation)

**Example:**
```bash
docker-compose run --rm kup --mode debug
```

### `--source <azure|github|both>`

Specifies which source(s) to collect PRs from:
- `azure`: Only Azure DevOps
- `github`: Only GitHub  
- `both`: Both sources (default if not specified)

**Example:**
```bash
docker-compose run --rm kup --source github
```

### `--days-before <N>`

Includes PRs merged up to N days before the start of the current month. Useful when the previous month's report was generated a few days before month-end, leaving some PRs uncaptured.

For example, if the current month is February, `--days-before 3` shifts the search window start from February 1 to January 29, so PRs merged on Jan 29–31 are included in the February report.

- Default: `0` (report starts from the 1st of the current month)
- Only affects the data collection window — the report title and working days remain for the current month

**Example:**
```bash
docker-compose run --rm kup --source github --days-before 3
```

## Environment Variables

### Required (Common)

| Variable | Description | Example |
|----------|-------------|---------|
| `AUTHOR_EMAIL` | Your email address for PR search | `john.doe@company.com` |
| `AUTHOR_TITLE` | Your job title | `Senior Software Engineer` |
| `MANAGER_EMAIL` | Your manager's email | `manager@company.com` |
| `MANAGER_TITLE` | Your manager's job title | `Engineering Manager` |

### Azure DevOps (Required if using `--source azure` or `both`)

| Variable | Description | How to Get |
|----------|-------------|------------|
| `AZURE_DEVOPS_EXT_PAT` | Personal Access Token (classic) | [Azure DevOps → User Settings → Personal Access Tokens](https://dev.azure.com/) |
| `AZURE_DEVOPS_ORG` | Azure DevOps organization name | Your organization name (e.g., `pdd-ihsmarkit`) |

**Required Azure DevOps PAT Scopes:**
- Code (Read)
- Work Items (Read)
- Project and Team (Read)

### GitHub (Required if using `--source github` or `both`)

| Variable | Description | How to Get |
|----------|-------------|------------|
| `GITHUB_TOKEN` | Personal Access Token | [GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic)](https://github.com/settings/tokens) |
| `GITHUB_ORG` | GitHub organization name | Your organization name (e.g., `octocat`) |

**Required GitHub Token Scopes:**
- `repo` (Full control of private repositories)
- `read:org` (Read org and team membership)

**⚠️ IMPORTANT - SSO Authorization:**

If your organization uses SSO (Single Sign-On), you **must** authorize your token:

1. Go to [GitHub Tokens Settings](https://github.com/settings/tokens)
2. Find your token in the list
3. Click **"Configure SSO"** button next to it
4. Click **"Authorize"** for your organization

Without SSO authorization, you'll get an error: `"The listed users and repositories cannot be searched"`

## How It Works

The tool collects and analyzes PRs using this workflow:

### For Each PR:

1. **Check PR Title** - Looks for `[KUP:<hours>]` pattern
2. **Check PR Description** - If not found in title, checks description
3. **Check PR Tags/Labels** - If still not found, checks tags
4. **Check Commits** - If still not found, scans all commit messages and sums hours
   - Implements smart deduplication to prevent counting the same commit multiple times across different PRs

### KUP Pattern Format:

The tool recognizes hours declarations in this format:
- `[KUP:1]` - Integer hours
- `[KUP:4.5]` - Decimal hours (using period)
- `[kup:2.5]` - Case insensitive
- `[KUP:3,5]` - Comma as decimal separator

### Output:

- **Console**: Shows progress, statistics, and warnings
- **PDF Report**: Generated in the `./out` directory with filename: `{Author Name}, {Year-Month}.pdf`
- **Work Statistics**: 
  - Personal utilization (accounting for absences)
  - Overall utilization
  - Warnings if >70% (suspicious) or <25% (too low)

## Project Structure

```
kup-generator/
├── lib/                    # Modular library files
│   ├── common.sh          # Shared utility functions
│   ├── azure-devops.sh    # Azure DevOps integration
│   └── github.sh          # GitHub integration
├── assets/                 # Static resources
│   ├── calendar.txt       # Working days calendar
│   ├── kup_report_template.tex  # LaTeX template
│   └── accuris-logo.png   # Company logo
├── report.sh              # Main entry point
├── docker-compose.yaml    # Docker Compose configuration
├── Dockerfile             # Docker image definition
└── readme.md             # This file
```

## Development

### Local Testing

```bash
# Build local image
docker build -t kup-generator:local .

# Run with local image
docker-compose run --rm kup
```

### Debugging

```bash
# Enable debug mode for detailed logs
docker-compose run --rm kup --mode debug
```
