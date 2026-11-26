# Contributing

Issues and focused pull requests are welcome. Describe the user-visible problem, the proposed behavior, and how you verified it.

## Local setup

Use macOS with Apple's Command Line Tools installed. No third-party packages are required.

```sh
bash scripts/test.sh
bash scripts/build.sh
open "build/Pankaj Mac Cleanup.app"
```

Tests create disposable temporary fixtures and clean up those fixtures afterward. Do not test deletion against personal documents or live application caches. `--scan-only` is an optional diagnostic against the current user's real caches; it is not part of CI.

## Review expectations

- Keep cache cleanup and personal-file handling separate.
- Do not add arbitrary-path deletion, automatic selection, administrator commands, background cleanup, or an empty-Trash action.
- A new cache entry needs a precise path, evidence that it is rebuildable, conservative process checks, and tests for its boundaries. Do not assume everything beneath a directory named “cache” is disposable.
- Keep personal-file moves recoverable and require confirmation for each exact file.
- Preserve path, symlink, stale-file, cloud, and running-process checks. Test behavior at the relevant boundary rather than reproducing implementation details.
- Document changes to deletion behavior, permissions, supported locations, logs, and known limitations.
- Keep local paths, cleanup logs, screenshots with personal information, credentials, build products, and crash reports out of commits and issues.

Before opening a pull request, run both test suites, build the app, and check `git diff --check`. For UI changes, inspect the affected native screen and describe manual testing limits. Report actual test results without claiming notarization, platform coverage, or OS integration tests that have not happened.

Security-sensitive findings belong in [private vulnerability reports](https://github.com/PANKAJBHADRECHA/mac-cleanup/security/advisories/new), not public issues.

## Enable GitHub Actions

A workflow template is provided at [`docs/ci/macos.yml`](docs/ci/macos.yml). It is not active. To enable it, use a GitHub login with permission to write workflows, copy the file to `.github/workflows/macos.yml`, and commit and push it. The template runs fixture-based tests, builds the app, and verifies its signature on macOS. No live-cache cleanup runs in CI.
