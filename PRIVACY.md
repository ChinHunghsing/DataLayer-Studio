# Privacy

DataLayer Studio works with local source videos and FIT activity files, which
can contain private location, health, and training data.

## App and CLI Data Flow

The app and command-line tool process input files locally on the Mac where they
run. The current implementation does not include analytics SDKs, custom in-app
event tracking, telemetry upload, account login, cloud sync, or network transfer code.
Source videos, exported overlays, layout presets, and rendered preview frames
are not uploaded.

If you enter an OpenWeather API key, DataLayer Studio can request hourly weather
from OpenWeather for the selected FIT activity. Those requests use the FIT
activity's approximate latitude, longitude, activity time, selected language,
and your OpenWeather API key. Source videos, rendered preview frames, exported
overlays, layout presets, heart-rate samples, cadence, pace, power, and the FIT
file itself are not sent to OpenWeather. Weather responses are cached locally to
avoid repeated requests while previewing or adjusting the timeline.

## Apple App Analytics

For App Store distribution, DataLayer Studio relies on Apple's
[App Store Connect Analytics](https://developer.apple.com/app-store-connect/analytics/)
and crash metrics to monitor aggregate app usage and stability. DataLayer Studio
does not add an analytics SDK or send custom analytics events. Apple's analytics
data is provided by Apple and is limited to users who have agreed to share
analytics with app developers.

## Local Files and Preferences

DataLayer Studio reads the video and FIT files you select, then writes the
output video to the path you choose. The GUI stores local preferences with
macOS `UserDefaults`, including layout presets, grid settings, distance unit,
and similar editor state. These preferences are local machine state and should
not be posted publicly in issues or pull requests. OpenWeather API keys are
stored in the macOS Keychain, and cached weather responses are stored in the
local user cache folder.

## Public Issues and Pull Requests

Do not upload private source videos, FIT/GPX/TCX files, GPS traces, heart-rate
data, screenshots with sensitive paths, signing material, or local preference
files to public issues or pull requests. Use small sanitized fixtures whenever
reproduction data is necessary.

## GitHub and Release Automation

GitHub Actions run only for repository events such as pull requests, pushes, and
release tags. Release automation builds and uploads release artifacts to GitHub
for tagged releases; it is separate from running the local app or CLI.

## Changes to This Policy

If a future contribution adds network access, analytics, cloud sync, crash
reporting, or any other data transfer, the pull request must update this file,
the user-facing documentation, and the source-available readiness checks before
the feature is merged.
