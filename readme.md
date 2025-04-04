# KUP Report generator
Collects all pull requests for current month and prepare PDF report according to provided template. Track only PRs, where `[KUP:<hours>]` text is in **title** or **description** fields. PDF file builds from LaTeX template.

# Run docker-compose

## Update docker-compose environments
1. `AZURE_DEVOPS_EXT_PAT` personal access token to Azure DevOps portal with all scopes (later will define only required)
2. `AUTHOR_EMAIL` contains your email for searching PRs;
3. `AUTHOR_TITLE` is your title;
4. `MANAGER_EMAIL` is your manager email;
5. `MANAGER_TITLE` is your manager's title;

## Mount requred volumes
1. Mount `out` folder for storing results;

## Run docker-compose

``` bash
docker-compose pull
docker-compose run --rm -- kup
```

# How it works 
Tool searches declared hours `[KUP:<HOURS>]` like this: `[KUP:1]` or `[kup:4.5]` in PRs and its commits messages, and build report in form of PDF file.

1. List of all pull requests sorts by creation date (ascending) and filtered by **current** month and PR author (`AUTHOR_EMAIL`);
2. Checks title and description of PR, if declared hours found in this places - then calculation stops and all commits marked as handled and go to the next PR;
3. Checks PR tags and looking for something like `[KUP:1]`;
4. Iterate over unhandled commits and find hours in title (comment). Sum all hours from commits;
5. No hours found in all places - skip current PR and move to the next one.
6. After processing all PRs - build PDF report.

