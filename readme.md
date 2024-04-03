# KUP Report generator
Collects all pull requests for current month and prepare PDF report according to provided template. Track only PRs, where `[KUP:<hours>]` text is in **title** or **description** fields. PDF file builds from LaTeX template.

# Prerequisites
1. `pdflatex` tool;
2. `az devops` tool;
3. `az devops login` and provide your PAT token with ability to access repos and workitems;
4. Update `AUTHOR`, `AUTHOR_ID`, `AUTHOR_EMAIL`, `PAT` in [report.sh](report.sh) to your actual values