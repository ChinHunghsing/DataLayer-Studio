# Privacy

DataLayer Studio works with local source videos and FIT activity files, which
can contain private location, health, and training data.

## App and CLI Data Flow

The app and command-line tool process input files locally on the device where
they run. The current implementation does not include analytics SDKs, custom
in-app event tracking, telemetry upload, account login, or background
network transfer code for source media. Source videos, activity files,
exported overlays, and rendered preview frames are not uploaded by DataLayer
Studio.

The app can synchronize user-created layout presets through Apple's iCloud
Key-Value Store when iCloud is available. Only the compact preset definition
(such as component types, positions, and appearance settings) and the selected
default preset are synchronized.
Source videos, activity files, GPS tracks, telemetry samples, preview frames,
and exported files are not included in preset synchronization. iCloud data is
handled by Apple under Apple's privacy policies. The command-line tool does not
use iCloud synchronization.

If you enter an OpenWeather API key, DataLayer Studio can request hourly weather
from OpenWeather for the selected FIT activity. Those requests use latitude and
longitude from the activity, the activity time, the selected language,
and your OpenWeather API key. Source videos, rendered preview frames, exported
overlays, layout presets, heart-rate samples, cadence, pace, power, and the FIT
file itself are not sent to OpenWeather. Weather responses are cached locally to
avoid repeated requests while previewing or adjusting the timeline.

The iOS subscription screen includes user-initiated links to Apple's standard
EULA and this privacy policy. Opening those links leaves the app and may contact
Apple or GitHub under their own privacy policies; DataLayer Studio does not send
source videos, activity files, layout presets, or rendered previews with those
links.

## Apple App Analytics

For App Store distribution, DataLayer Studio relies on Apple's
[App Store Connect Analytics](https://developer.apple.com/app-store-connect/analytics/)
and crash metrics to monitor aggregate app usage and stability. DataLayer Studio
does not add an analytics SDK or send custom analytics events. Apple's analytics
data is provided by Apple and is limited to users who have agreed to share
analytics with app developers.

## Local Files and Preferences

DataLayer Studio reads the video and FIT files you select, then writes the
output video to the path you choose. The GUI stores preferences with the
platform's `UserDefaults`, including a local copy of layout presets, grid
settings, distance unit, and similar editor state. Layout presets may also be
synchronized through Apple's iCloud service as described above. OpenWeather API
keys are stored in local app preferences; after upgrading from an older
version, a legacy macOS Keychain copy may remain temporarily for migration or
rollback. The OpenWeather API key is not synchronized through iCloud. Cached
weather responses are stored in the local user cache folder.
Do not post these local preference or cache files publicly in issues or pull
requests.

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

If a future contribution changes network access, analytics, cloud sync, crash
reporting, or any other data transfer, the pull request must update this file,
the user-facing documentation, and the source-available readiness checks before
the feature is merged.
