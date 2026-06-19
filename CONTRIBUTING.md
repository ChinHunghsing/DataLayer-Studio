# Contributing to DataLayer Studio

Thanks for helping improve DataLayer Studio. This project is source-available
for noncommercial use under the terms in [LICENSE.md](LICENSE.md), and
contributions must be compatible with that license.

## License Expectations

By intentionally submitting a pull request, issue attachment, patch, or other
contribution, you agree that your contribution is licensed under the same
license as this project:

- PolyForm Noncommercial License 1.0.0
- DataLayer Studio Source-Share Addendum in [LICENSE.md](LICENSE.md)

No separate contributor license agreement is required right now. The
contribution license in [LICENSE.md](LICENSE.md) and the pull request checklist
are the source of truth for contribution licensing.

Only submit work that you have the right to contribute. Do not copy code,
assets, UI artwork, icons, screenshots, or proprietary implementation details
from commercial software or from projects with incompatible licenses.
Do not submit code, assets, icons, screenshots, or implementation details copied
from Telemetry Overlay or any other third-party commercial app.

If your change adds a dependency, externally sourced asset, generated code, or
adapted example, include the source, license, and attribution requirements in
the PR. Update [NOTICE.md](NOTICE.md) when attribution, notices, or license
compatibility need to be recorded.

## Before Opening a Pull Request

1. Keep the change focused.
2. Match the existing Swift and SwiftUI style.
3. Add or update tests when behavior changes.
4. Update documentation when commands, workflows, or user-facing behavior
   changes.
5. For GUI-visible changes, make sure the app can be rebuilt and launched from
   the current source.
6. Do not force-add ignored private videos, FIT/GPX/TCX activity data, signing
   files, generated archives, or local environment files.

## Data Safety

Running data, GPS traces, source videos, crash logs, screenshots, and local file
paths can expose private information. Before opening an issue or PR:

- Redact personal locations, names, device identifiers, and account details.
- Prefer minimal synthetic FIT fixtures when tests need telemetry data.
- Do not attach private videos, FIT/GPX/TCX files, exported overlays, or logs
  unless you are comfortable making them public.
- Use [SECURITY.md](SECURITY.md) instead of a public issue when the report
  involves a vulnerability or private data exposure.

## Local Development

Build the package:

```bash
swift build
```

Build release products checked by CI:

```bash
swift build -c release --product overlay
swift build -c release --product datalayer-studio
```

Run tests:

```bash
swift test
```

Run repository readiness checks:

```bash
scripts/verify_source_available_readiness.sh
```

Run the GUI from SwiftPM:

```bash
swift run datalayer-studio
```

Build a local app bundle:

```bash
scripts/build_app_bundle.sh
open ".build/DataLayer Studio.app"
```

Run the command-line tool:

```bash
swift run overlay --help
```

## Verification Notes

Choose checks that match the change:

- Parser, telemetry, layout, renderer, or CLI behavior: add focused tests and
  run `swift test`.
- Package, source, resource, or release workflow changes: run the release
  product builds listed above.
- GUI-visible changes: rebuild and launch the app, then describe what was
  manually checked in the PR.
- Packaging, icon, legal, or release-facing changes: run
  `scripts/build_app_bundle.sh` and `scripts/verify_app_bundle.sh`.
- License, privacy, dependency, data-handling, or public documentation changes:
  run `scripts/verify_source_available_readiness.sh`.

## Pull Request Checklist

- The PR describes what changed and why.
- `scripts/verify_source_available_readiness.sh` passes locally, or the PR explains
  why it could not be run.
- `swift test` passes locally, or the PR explains why it could not be run.
- Release product builds pass when sources, package metadata, resources, or
  release workflows changed.
- GUI-visible changes include manual verification notes.
- New dependencies, externally sourced assets, generated code, or adapted
  examples include provenance and license notes.
- The change does not introduce sample videos, FIT files, personal activity
  data, credentials, generated build output, or local machine state.
- The contribution is compatible with the project license.

## What Maintainers Look For

- Clear, narrow diffs.
- Tests covering parser, renderer, CLI, or UI model behavior when applicable.
- No unrelated refactors mixed into feature or bug-fix PRs.
- No private telemetry files, local preferences, or generated `.build` output.
