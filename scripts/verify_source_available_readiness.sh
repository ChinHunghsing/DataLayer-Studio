#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

fail() {
    echo "error: $*" >&2
    failures=$((failures + 1))
}

require_file() {
    local path="$1"
    if [[ ! -f "$path" ]]; then
        fail "missing required file: $path"
    fi
}

require_gitignore_pattern() {
    local pattern="$1"
    if ! grep -q "$pattern" .gitignore; then
        fail ".gitignore must include pattern: $pattern"
    fi
}

require_no_pattern_in_paths() {
    local pattern="$1"
    local message="$2"
    shift 2

    local matches
    matches="$(grep -RInE "$pattern" "$@" 2>/dev/null || true)"
    if [[ -n "$matches" ]]; then
        fail "$message: $matches"
    fi
}

required_files=(
    "README.md"
    "LICENSE.md"
    "NOTICE.md"
    "CONTRIBUTING.md"
    "CODE_OF_CONDUCT.md"
    "PRIVACY.md"
    "SECURITY.md"
    "SUPPORT.md"
    "MAINTAINERS.md"
    ".gitignore"
    ".github/CODEOWNERS"
    ".github/pull_request_template.md"
    ".github/ISSUE_TEMPLATE/bug_report.yml"
    ".github/ISSUE_TEMPLATE/feature_request.yml"
    ".github/ISSUE_TEMPLATE/config.yml"
    ".github/workflows/ci.yml"
    ".github/workflows/release.yml"
    ".github/dependabot.yml"
    "scripts/verify_source_available_readiness.sh"
    "scripts/verify_app_bundle.sh"
)

for path in "${required_files[@]}"; do
    require_file "$path"
done

require_gitignore_pattern '^\.build/$'
require_gitignore_pattern '^\.colameta/$'
require_gitignore_pattern '^\*\.fit$'
require_gitignore_pattern '^\*\.gpx$'
require_gitignore_pattern '^\*\.tcx$'
require_gitignore_pattern '^\*\.mov$'
require_gitignore_pattern '^\*\.mp4$'
require_gitignore_pattern '^\*\.m4v$'
require_gitignore_pattern '^\*\.avi$'
require_gitignore_pattern '^\*\.mkv$'
require_gitignore_pattern '^\*\.zip$'
require_gitignore_pattern '^\*\.cer$'
require_gitignore_pattern '^\*\.certSigningRequest$'
require_gitignore_pattern '^\*\.crt$'
require_gitignore_pattern '^\*\.csr$'
require_gitignore_pattern '^\*\.der$'
require_gitignore_pattern '^\*\.key$'
require_gitignore_pattern '^\*\.pem$'
require_gitignore_pattern '^\*\.p8$'
require_gitignore_pattern '^\*\.p12$'
require_gitignore_pattern '^\*\.mobileprovision$'
require_gitignore_pattern '^\*\.provisionprofile$'
require_gitignore_pattern '^\*\.xcarchive$'
require_gitignore_pattern '^\*\.xcarchive/$'
require_gitignore_pattern '^\.env$'
require_gitignore_pattern '^\.env\.\*$'
require_gitignore_pattern '^!\.env\.example$'

tracked_local_state="$(git ls-files '.build/*' '.colameta/*')"
if [[ -n "$tracked_local_state" ]]; then
    fail "tracked local build/state files found: $tracked_local_state"
fi

while IFS= read -r path; do
    case "$path" in
        *.fit|*.FIT|*.gpx|*.GPX|*.tcx|*.TCX|*.mov|*.MOV|*.mp4|*.MP4|*.m4v|*.M4V|*.avi|*.AVI|*.mkv|*.MKV|*.cer|*.certSigningRequest|*.crt|*.csr|*.der|*.key|*.pem|*.p8|*.p12|*.mobileprovision|*.provisionprofile|*.xcarchive/*|*.zip)
            fail "tracked private or generated artifact: $path"
            ;;
        .env|.env.local|.private.env|*.private.env)
            fail "tracked local secret/env file: $path"
            ;;
    esac
done < <(git ls-files)

require_no_pattern_in_paths 'URLSession|URLRequest|NSURLConnection|NWConnection|WKWebView|ASWebAuthenticationSession|^[[:space:]]*import[[:space:]]+Network[[:space:]]*$|https?://' \
    "source code must not add network transfer APIs without updating privacy policy" \
    Sources
require_no_pattern_in_paths 'Sentry|Firebase|Crashlytics|analytics' \
    "source or package metadata must not add analytics/crash reporting dependencies without updating privacy policy" \
    Sources Package.swift

grep -q 'LEGAL_DIR' scripts/build_app_bundle.sh || fail "app bundle script must define LEGAL_DIR"
grep -q 'LICENSE.md' scripts/build_app_bundle.sh || fail "app bundle script must copy LICENSE.md"
grep -q 'NOTICE.md' scripts/build_app_bundle.sh || fail "app bundle script must copy NOTICE.md"
grep -q 'README.md' scripts/build_app_bundle.sh || fail "app bundle script must copy README.md"

grep -q '## License' README.md || fail "README.md must include a License section"
grep -q '## Contributing' README.md || fail "README.md must include a Contributing section"
grep -q '## Release' README.md || fail "README.md must include a Release section"
grep -q 'independent project' README.md || fail "README.md must identify DataLayer Studio as independent"
grep -q 'not affiliated with' README.md || fail "README.md must include third-party affiliation disclaimer"
grep -q 'proprietary code or assets from Telemetry Overlay' README.md || fail "README.md must disclaim Telemetry Overlay proprietary assets"
grep -q 'scripts/verify_source_available_readiness.sh' README.md || fail "README.md must document the readiness check"
grep -q 'PRIVACY.md' README.md || fail "README.md must link to PRIVACY.md"
readme_release_section="$(sed -n '/When a `v\*` tag is pushed/,/The app bundle includes/p' README.md)"
[[ "$readme_release_section" == *"verify_source_available_readiness.sh"* ]] || fail "README.md release section must mention readiness verification"
[[ "$readme_release_section" == *"release products"* ]] || fail "README.md release section must mention release product builds"
[[ "$readme_release_section" == *"legal files"* ]] || fail "README.md release section must mention bundled legal files"
grep -q 'does not include analytics' PRIVACY.md || fail "PRIVACY.md must state the current analytics behavior"
grep -q 'network transfer code' PRIVACY.md || fail "PRIVACY.md must state the current network transfer behavior"
grep -q 'UserDefaults' PRIVACY.md || fail "PRIVACY.md must document local preference storage"
grep -q 'network access, analytics, cloud sync, crash' PRIVACY.md || fail "PRIVACY.md must require updates when network or analytics behavior changes"
grep -q 'swift test' CONTRIBUTING.md || fail "CONTRIBUTING.md must document swift test"
grep -qi 'license' CONTRIBUTING.md || fail "CONTRIBUTING.md must mention license expectations"
grep -q 'No separate contributor license agreement' CONTRIBUTING.md || fail "CONTRIBUTING.md must clarify CLA expectations"
grep -q 'NOTICE.md' CONTRIBUTING.md || fail "CONTRIBUTING.md must explain third-party notice updates"
grep -q 'Telemetry Overlay' CONTRIBUTING.md || fail "CONTRIBUTING.md must forbid copying from Telemetry Overlay"
grep -q 'Data Safety' CONTRIBUTING.md || fail "CONTRIBUTING.md must include data safety guidance"
grep -q 'verify_app_bundle.sh' CONTRIBUTING.md || fail "CONTRIBUTING.md must document app bundle verification"
grep -q 'Release product builds' CONTRIBUTING.md || fail "CONTRIBUTING.md checklist must require release product builds when applicable"
grep -q 'High-Risk Changes' MAINTAINERS.md || fail "MAINTAINERS.md must define high-risk changes"
grep -q 'Merge Discipline' MAINTAINERS.md || fail "MAINTAINERS.md must define merge discipline"
grep -q 'release product builds' MAINTAINERS.md || fail "MAINTAINERS.md must require release product builds"
grep -q 'CODEOWNERS' MAINTAINERS.md || fail "MAINTAINERS.md must reference CODEOWNERS review"
grep -q 'PRIVACY.md' MAINTAINERS.md || fail "MAINTAINERS.md must require privacy documentation updates"
grep -q 'Source-available readiness check passes' .github/pull_request_template.md || fail "PR template must require readiness verification"
grep -q 'NOTICE.md' .github/pull_request_template.md || fail "PR template must mention NOTICE.md for third-party notices"
grep -q 'PRIVACY.md' .github/pull_request_template.md || fail "PR template must require privacy documentation checks"
grep -q 'GPS traces' .github/pull_request_template.md || fail "PR template must warn about GPS traces"
grep -q 'generated build output' .github/pull_request_template.md || fail "PR template must warn about generated build output"
grep -q 'Third-Party Product References' NOTICE.md || fail "NOTICE.md must include third-party product reference disclaimers"
grep -q 'not affiliated with' NOTICE.md || fail "NOTICE.md must include affiliation disclaimer"
grep -q 'proprietary code, assets, icons, screenshots, or implementation details' NOTICE.md || fail "NOTICE.md must disclaim copied third-party material"
grep -q 'Data safety' .github/ISSUE_TEMPLATE/bug_report.yml || fail "bug report template must require data safety confirmation"
grep -q 'GPS traces' .github/ISSUE_TEMPLATE/bug_report.yml || fail "bug report template must warn about GPS traces"
grep -q 'Data safety' .github/ISSUE_TEMPLATE/feature_request.yml || fail "feature request template must require data safety confirmation"
grep -q 'GPS traces' .github/ISSUE_TEMPLATE/feature_request.yml || fail "feature request template must warn about GPS traces"
grep -q '^blank_issues_enabled: false$' .github/ISSUE_TEMPLATE/config.yml || fail "blank issues must be disabled so templates capture data safety checks"

grep -q 'scripts/verify_source_available_readiness.sh' .github/workflows/ci.yml || fail "CI must run readiness verification"
grep -q 'swift build -c release --product overlay' .github/workflows/ci.yml || fail "CI must build the overlay release product"
grep -q 'swift build -c release --product datalayer-studio' .github/workflows/ci.yml || fail "CI must build the datalayer-studio release product"
grep -q 'swift test' .github/workflows/ci.yml || fail "CI must run swift test"
grep -q 'scripts/verify_source_available_readiness.sh' .github/workflows/release.yml || fail "release workflow must run readiness verification"
grep -q 'scripts/verify_app_bundle.sh' .github/workflows/release.yml || fail "release workflow must verify the app bundle"
grep -q 'swift build -c release --product overlay' .github/workflows/release.yml || fail "release workflow must build the overlay release product"
grep -q 'swift build -c release --product datalayer-studio' .github/workflows/release.yml || fail "release workflow must build the datalayer-studio release product"
grep -q 'swift test' .github/workflows/release.yml || fail "release workflow must run swift test"

grep -q '@leeeboo' .github/CODEOWNERS || fail "CODEOWNERS must name the current repository owner"
grep -q 'https://polyformproject.org/licenses/noncommercial/1.0.0' LICENSE.md || fail "LICENSE.md must contain the canonical PolyForm Noncommercial URL"

if (( failures > 0 )); then
    exit 1
fi

echo "Source-available readiness checks passed."
