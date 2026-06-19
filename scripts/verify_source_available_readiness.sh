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

required_files=(
    "README.md"
    "LICENSE.md"
    "NOTICE.md"
    "CONTRIBUTING.md"
    "CODE_OF_CONDUCT.md"
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

grep -q '^\.build/$' .gitignore || fail ".gitignore must ignore .build/"
grep -q '^\.colameta/$' .gitignore || fail ".gitignore must ignore .colameta/"

tracked_local_state="$(git ls-files '.build/*' '.colameta/*')"
if [[ -n "$tracked_local_state" ]]; then
    fail "tracked local build/state files found: $tracked_local_state"
fi

while IFS= read -r path; do
    case "$path" in
        *.fit|*.FIT|*.mov|*.MOV|*.mp4|*.MP4|*.m4v|*.M4V|*.p8|*.p12|*.mobileprovision|*.xcarchive/*|*.zip)
            fail "tracked private or generated artifact: $path"
            ;;
        .env|.env.local|.private.env|*.private.env)
            fail "tracked local secret/env file: $path"
            ;;
    esac
done < <(git ls-files)

grep -q 'LEGAL_DIR' scripts/build_app_bundle.sh || fail "app bundle script must define LEGAL_DIR"
grep -q 'LICENSE.md' scripts/build_app_bundle.sh || fail "app bundle script must copy LICENSE.md"
grep -q 'NOTICE.md' scripts/build_app_bundle.sh || fail "app bundle script must copy NOTICE.md"
grep -q 'README.md' scripts/build_app_bundle.sh || fail "app bundle script must copy README.md"

grep -q '## License' README.md || fail "README.md must include a License section"
grep -q '## Contributing' README.md || fail "README.md must include a Contributing section"
grep -q '## Release' README.md || fail "README.md must include a Release section"
grep -q 'scripts/verify_source_available_readiness.sh' README.md || fail "README.md must document the readiness check"
grep -q 'swift test' CONTRIBUTING.md || fail "CONTRIBUTING.md must document swift test"
grep -qi 'license' CONTRIBUTING.md || fail "CONTRIBUTING.md must mention license expectations"

grep -q 'scripts/verify_source_available_readiness.sh' .github/workflows/ci.yml || fail "CI must run readiness verification"
grep -q 'swift test' .github/workflows/ci.yml || fail "CI must run swift test"
grep -q 'scripts/verify_source_available_readiness.sh' .github/workflows/release.yml || fail "release workflow must run readiness verification"
grep -q 'scripts/verify_app_bundle.sh' .github/workflows/release.yml || fail "release workflow must verify the app bundle"
grep -q 'swift test' .github/workflows/release.yml || fail "release workflow must run swift test"

grep -q '@leeeboo' .github/CODEOWNERS || fail "CODEOWNERS must name the current repository owner"
grep -q 'https://polyformproject.org/licenses/noncommercial/1.0.0' LICENSE.md || fail "LICENSE.md must contain the canonical PolyForm Noncommercial URL"

if (( failures > 0 )); then
    exit 1
fi

echo "Source-available readiness checks passed."
