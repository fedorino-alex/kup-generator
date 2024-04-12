# KUP Report generator
Collects all pull requests for current month and prepare PDF report according to provided template. Track only PRs, where `[KUP:<hours>]` text is in **title** or **description** fields. PDF file builds from LaTeX template.

# Prerequisites
1. `pdflatex` tool;
2. `azure-cli` tool;
3. `az devops` extension;
4. `jq` tool;
s
# Environment
1. `AUTHOR_EMAIL` contains email of PRs author;
2. `AZURE_DEVOPS_EXT_PAT` contains Personal Access Token (PAT) to azure devops portal.

# Calculations
1. List of all pull requests sorts by creation date (ascending);
2. Check title and description of Pull Request (PR), if declared hours found in this places - then calculation stops and all commits marked as handled and go to the next PR;
3. Iterate over unhandled commits and find hours in title (comment). Sum all hours from commits;
4. No hours found in all places - skip current PR and move to the next one.