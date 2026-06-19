# Maintainers

This project is maintained by Leeeboo.

DataLayer Studio is source-available for noncommercial use. Maintainers should
keep reviews practical and narrow, but every accepted contribution must remain
compatible with [LICENSE.md](LICENSE.md).

## Review Policy

Before merging a pull request, confirm:

- The change is focused and described clearly.
- New behavior has tests, or the PR explains why tests are not appropriate.
- `scripts/verify_source_available_readiness.sh` passes.
- Release product builds pass for changes that touch Swift sources, package
  metadata, resources, packaging, or release workflows.
- `swift test` passes, or the PR documents a reproducible local failure.
- GUI-visible changes include rebuild or launch notes from the contributor.
- The PR does not include private videos, FIT files, GPS/activity data,
  credentials, generated build output, local preference files, or machine state.
- New dependencies, copied assets, generated code, and imported examples are
  license-compatible with this project's noncommercial source-share terms, and
  `NOTICE.md` is updated when attribution or third-party notices are required.
- Changes to privacy, network access, analytics, cloud sync, crash reporting,
  account behavior, or user data handling update `PRIVACY.md`, user-facing
  documentation, and the readiness checks.

## High-Risk Changes

Use focused maintainer review for changes that affect:

- New dependencies, copied assets, generated code, imported examples, or
  third-party source snippets.
- Network access, analytics, cloud sync, crash reporting, account/login
  behavior, or external services.
- File parsing, export, rendering, or preview behavior that touches user source
  videos, FIT files, GPS routes, heart-rate samples, or activity data.
- Release packaging, signing, notarization, legal documents, CI, release
  workflows, or bundled resources.
- Licensing, trademarks, product naming, privacy claims, or public project
  positioning.

High-risk PRs need explicit verification notes that explain what was checked,
which user data paths were affected, and whether any legal/privacy files needed
updates.

## Merge Discipline

Do not merge:

- Failing or skipped CI checks unless the maintainer records the reason and the
  remaining risk in the PR.
- Draft PRs, unresolved review discussions, or changes without a clear summary.
- Large generated diffs that are not required to build or release the project.
- Private media, activity traces, credentials, local paths, build output, or
  machine-specific files.

Prefer small PRs. Ask contributors to split unrelated behavior, UI, packaging,
and policy changes. Use `.github/CODEOWNERS` review for policy, release, legal,
workflow, and script changes.

## Release Policy

Before pushing a release tag:

- Run `scripts/verify_source_available_readiness.sh`.
- Run `swift test`.
- Run release product builds for `overlay` and `datalayer-studio`.
- Build the app bundle with `scripts/build_app_bundle.sh` when release-facing
  files, packaging, icons, localization, or GUI-visible behavior changed.
- Run `scripts/verify_app_bundle.sh` to confirm the bundle includes
  `LICENSE.md`, `NOTICE.md`, and `README.md` under `Contents/Resources/Legal`.

## Data Handling

Issue attachments and pull requests can easily expose private location and
training data. Ask contributors to remove or redact personal FIT files, videos,
screenshots, logs, and paths before sharing them publicly. Use private security
reporting for vulnerabilities or sensitive data exposure.
