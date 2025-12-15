# Contributing to KUP Generator

## Conventional Commits

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for automatic semantic versioning. Please follow this format for your commit messages:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

- **feat**: A new feature (triggers minor version bump)
- **fix**: A bug fix (triggers patch version bump)
- **docs**: Documentation only changes (triggers patch version bump)
- **style**: Changes that do not affect the meaning of the code (white-space, formatting, etc)
- **refactor**: A code change that neither fixes a bug nor adds a feature (triggers patch version bump)
- **perf**: A code change that improves performance (triggers patch version bump)
- **test**: Adding missing tests or correcting existing tests
- **build**: Changes that affect the build system or external dependencies (triggers patch version bump)
- **ci**: Changes to CI configuration files and scripts
- **chore**: Other changes that don't modify src or test files
- **revert**: Reverts a previous commit (triggers patch version bump)

### Breaking Changes

For breaking changes, add `BREAKING CHANGE:` in the footer or add `!` after the type:

```
feat!: remove deprecated API endpoint

BREAKING CHANGE: The /old-api endpoint has been removed. Use /new-api instead.
```

This will trigger a major version bump.

### Examples

```bash
# Minor version bump (new feature)
feat: add support for custom date ranges in reports

# Patch version bump (bug fix)
fix: resolve percentage calculation rounding error

# Patch version bump (refactoring)
refactor: replace bc with awk for floating-point arithmetic

# No version bump
chore: update README documentation

# Major version bump (breaking change)
feat!: change report output format to JSON

BREAKING CHANGE: Report output is now in JSON format instead of LaTeX
```

## Semantic Versioning

This project follows [Semantic Versioning](https://semver.org/):

- **MAJOR** version when you make incompatible API changes
- **MINOR** version when you add functionality in a backwards compatible manner
- **PATCH** version when you make backwards compatible bug fixes

Version bumping is handled automatically by semantic-release based on your commit messages when PRs are merged to the main branch.

