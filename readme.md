# KUP Report generator
Collects all pull requests for current month and prepare PDF report according to provided template. Track only PRs, where `[KUP:<hours>]` text is in **title** or **description** fields. PDF file builds from LaTeX template.

# Prerequisites
1. `pdflatex` tool;
2. `az devops` tool;
3. `az devops login` and provide your PAT token with ability to access repos and workitems;
4. Update `AUTHOR`, `AUTHOR_ID`, `AUTHOR_EMAIL`, `PAT` in [report.sh](report.sh) to your actual values

# Calculations
1. List of all pull requests sorts by creation date (ascending);
2. Check title and description of Pull Request (PR), if declared hours found in this places - then calculation stops and all commits marked as handled and go to the next PR;
3. Iterate over unhandled commits and find hours in title (comment). Sum all hours from commits;
4. No hours found in all places - skip current PR and move to the next one.