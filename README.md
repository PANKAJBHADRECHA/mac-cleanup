# Pankaj Mac Cleanup

**A small native macOS utility for deliberate, manual cleanup.**

Review rebuildable caches, inspect large local files, and decide exactly what to remove. Built with Swift and SwiftUI, using macOS frameworks and command-line utilities—no third-party packages, AI subscription, or background service.

[![Release](https://img.shields.io/github/v/release/PANKAJBHADRECHA/mac-cleanup)](https://github.com/PANKAJBHADRECHA/mac-cleanup/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)

[Get started](#getting-started) · [Usage guide](docs/USAGE.md) · [Safety and privacy](docs/SAFETY.md) · [Releases](https://github.com/PANKAJBHADRECHA/mac-cleanup/releases)

## Two workflows, explicit choices

### Quick clean

Scan a fixed list of cache locations, see their sizes and exact paths, then select what to clear. The app checks for associated running apps and package tools before deletion. Nothing is selected automatically.

Supported caches: **Chrome, Spotify, Firefox, Comet, pip, npm, Homebrew, Go, node-gyp, and TypeScript**.

### Review files

Choose a local folder inside **Documents, Downloads, or Desktop**. Review files largest first, filter by size, check modification dates, and reveal items in Finder. Each file requires its own confirmation before moving to macOS Trash.

The app checks the latest accessible Time Machine backup before folder selection and asks whether to continue if it cannot verify a recent backup.

> **Deletion behavior:** Cache cleanup permanently removes selected cache folders. File review moves individually confirmed files to Trash. Moving files to Trash does not reclaim space until you empty it yourself. This app never empties Trash.

## Getting started

**Requirements:** macOS 13 or later. Building requires Apple's Command Line Tools, including Swift. The compiled app requires no separate runtime installation.

```sh
git clone https://github.com/PANKAJBHADRECHA/mac-cleanup.git
cd mac-cleanup
bash scripts/test.sh
bash scripts/build.sh
open "build/Pankaj Mac Cleanup.app"
```

To install into your user Applications folder, quit any running copy and run:

```sh
bash Install.command
```

The installer tests, builds, copies, and opens the app. **It does not perform a cleanup.** If Apple's Command Line Tools are missing, it prints installation guidance rather than downloading them automatically.

Prebuilt **Apple Silicon** downloads are available in [Releases](https://github.com/PANKAJBHADRECHA/mac-cleanup/releases/latest). Builds are ad-hoc signed, **not Developer ID signed or notarized**. A downloaded build may be blocked by Gatekeeper; building locally is the documented path. Do not disable macOS security protections to run it. Intel source builds are intended to work but have not been validated on Intel hardware.

The installed v1.1 app measured approximately **780 KiB** on the development Mac. Compiler tools and build caches are separate and can be much larger; no storage savings are guaranteed.

## Designed for review before removal

- **Bounded scope:** Cache deletion uses a built-in path allowlist; file review stays within the folder you choose.
- **Fresh checks:** Paths and file identity are rechecked before removal. Changed files or substantially grown caches require another scan.
- **Protected locations:** System files, snapshots, browser profiles, Photos libraries, and iCloud locations reported by macOS are excluded from cleanup.
- **Manual operation:** No scheduled tasks, login items, administrator commands, or silent cleanup.
- **Local history:** Cleanup outcomes remain on the Mac. The app makes no network requests and uploads no logs.

Filesystem checks reduce risk but cannot eliminate concurrent changes. Process detection is best effort. Close relevant apps, pause installs, keep a backup, and review the displayed paths. See [Safety and privacy](docs/SAFETY.md) for the exact boundaries and limitations.

## Development

The project uses direct `swiftc` builds and two standalone test executables; no package manager is required.

```sh
# Run both suites using disposable temporary fixtures
bash scripts/test.sh

# Build and ad-hoc sign the app bundle
bash scripts/build.sh

# Optional: inspect actual supported caches without deleting anything
bash scripts/test.sh --scan-only
```

The suites contain **40 checks** covering cache allowlists, symlinks, running processes, stale file snapshots, folder boundaries, file filters, Trash behavior, and backup warnings. Tests simulate document moves in a temporary directory; they do not move personal files into the real Trash. A [macOS CI template](docs/ci/macos.yml) is included; automated checks are not enabled yet. Native dialogs and real Trash integration still require manual verification.

### Source layout

- [`Sources/CleanupCore.swift`](Sources/CleanupCore.swift) — cache scanning, validation, cleanup, and audit history.
- [`Sources/FileReviewCore.swift`](Sources/FileReviewCore.swift) — local file review, Trash moves, and backup checks.
- [`Sources/MacCleanup.swift`](Sources/MacCleanup.swift) and [`Sources/FileReviewUI.swift`](Sources/FileReviewUI.swift) — SwiftUI screens and app lifecycle.
- [`Tests/`](Tests/) — disposable filesystem fixtures and safety checks.
- [`scripts/`](scripts/) — build and test entry points.

See [Contributing](CONTRIBUTING.md) for development expectations and [Changelog](CHANGELOG.md) for release history. For security issues, use the private reporting route in [SECURITY.md](SECURITY.md).

## Acknowledgements

Inspired by [Kunwar1417/mac-cleanup](https://github.com/Kunwar1417/mac-cleanup), an instruction-based AI cleanup assistant. This project is an independent native implementation with a narrower scope: selected cache cleanup and individually confirmed local-file moves to Trash. No upstream code or instruction text is bundled.

## License

[MIT](LICENSE) · Copyright © 2026 Pankaj Bhadrecha.
