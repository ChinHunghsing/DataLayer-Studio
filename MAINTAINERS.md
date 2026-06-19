# Maintainers

This project is maintained by Leeeboo.

DataLayer Studio is source-available for noncommercial use. Maintainers should
keep reviews practical and narrow, but every accepted contribution must remain
compatible with [LICENSE.md](LICENSE.md).

## Review Policy

Before merging a pull request, confirm:

- The change is focused and described clearly.
- New behavior has tests, or the PR explains why tests are not appropriate.
- `scripts/verify_open_source_readiness.sh` passes.
- `swift test` passes, or the PR documents a reproducible local failure.
- GUI-visible changes include rebuild or launch notes from the contributor.
- The PR does not include private videos, FIT files, GPS/activity data,
  credentials, generated build output, local preference files, or machine state.
- New dependencies, copied assets, generated code, and imported examples are
  license-compatible with this project's noncommercial source-share terms.

## Release Policy

Before pushing a release tag:

- Run `scripts/verify_open_source_readiness.sh`.
- Run `swift test`.
- Build the app bundle with `scripts/build_app_bundle.sh` when release-facing
  files, packaging, icons, localization, or GUI-visible behavior changed.
- Run `scripts/verify_app_bundle.sh` to confirm the bundle includes
  `LICENSE.md`, `NOTICE.md`, and `README.md` under `Contents/Resources/Legal`.

## Data Handling

Issue attachments and pull requests can easily expose private location and
training data. Ask contributors to remove or redact personal FIT files, videos,
screenshots, logs, and paths before sharing them publicly. Use private security
reporting for vulnerabilities or sensitive data exposure.
