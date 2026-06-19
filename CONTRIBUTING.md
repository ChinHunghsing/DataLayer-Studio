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

Only submit work that you have the right to contribute. Do not copy code,
assets, UI artwork, icons, screenshots, or proprietary implementation details
from commercial software or from projects with incompatible licenses.

## Before Opening a Pull Request

1. Keep the change focused.
2. Match the existing Swift and SwiftUI style.
3. Add or update tests when behavior changes.
4. Update documentation when commands, workflows, or user-facing behavior
   changes.
5. For GUI-visible changes, make sure the app can be rebuilt and launched from
   the current source.

## Local Development

Build the package:

```bash
swift build
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

## Pull Request Checklist

- The PR describes what changed and why.
- `scripts/verify_source_available_readiness.sh` passes locally, or the PR explains
  why it could not be run.
- `swift test` passes locally, or the PR explains why it could not be run.
- GUI-visible changes include manual verification notes.
- The change does not introduce sample videos, FIT files, personal activity
  data, credentials, generated build output, or local machine state.
- The contribution is compatible with the project license.

## What Maintainers Look For

- Clear, narrow diffs.
- Tests covering parser, renderer, CLI, or UI model behavior when applicable.
- No unrelated refactors mixed into feature or bug-fix PRs.
- No private telemetry files, local preferences, or generated `.build` output.
