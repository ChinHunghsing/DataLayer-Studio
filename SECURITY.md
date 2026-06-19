# Security Policy

## Supported Versions

Security fixes are accepted against the `main` branch unless a release branch is
explicitly announced.

## Reporting a Vulnerability

Please do not open a public issue for vulnerabilities, private keys, personal
activity data exposure, or anything that could put users at risk.

Use GitHub private vulnerability reporting or a private GitHub security advisory
for this repository when available. If private reporting is not enabled, open a
minimal public issue saying that you need a private maintainer contact, without
including exploit details, secrets, personal data, or reproduction files.

Include:

- affected version or commit
- platform and macOS version
- a concise impact description
- safe reproduction steps
- whether the issue involves local files, generated videos, FIT activity data,
  or exported layout presets

## Data Handling Notes

DataLayer Studio works with local videos and FIT activity files. Bug reports and
pull requests should avoid uploading personal videos, GPS traces, heart-rate
data, or other private activity data unless the contributor has intentionally
created a sanitized fixture.

