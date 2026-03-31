# Branch promotion policy (`development` → `uat` → `main`)

This repo uses a three-stage promotion model:

1. `development` is the day-to-day integration branch.
2. `uat` receives release-candidate PRs only from `development`.
3. `main` receives production PRs only from `uat`.

## What is automated in-repo

The GitHub Actions workflow at `.github/workflows/enforce-promotion-flow.yml` enforces:

- PRs with base `uat` must come from `development`.
- PRs with base `main` must come from `uat`.

To make these checks mandatory, enable branch protection status checks on `uat` and `main` and require this workflow/job to pass.

## Required repository settings (GitHub UI)

Apply these in **Settings → Branches**:

### `main`
- Require a pull request before merging.
- Require at least 1 approval.
- Require status checks to pass (include the workflow job above).
- Restrict push access (admins/release bot only).
- (Optional) Require signed commits.
- (Recommended) Include administrators.

### `uat`
- Require a pull request before merging.
- Require at least 1 approval.
- Require status checks to pass (include the workflow job above).
- Restrict push access to release maintainers.
- (Recommended) Include administrators.

## Additional recommended setting

Enable **Settings → General → Pull Requests → Automatically delete head branches**.

## Notes

GitHub branch protection itself cannot be fully configured from normal repository files. The workflow in this repo enforces source-branch rules at PR time; branch protections and default-branch changes must be configured in GitHub repository settings (or via GitHub API/CLI by an admin).
