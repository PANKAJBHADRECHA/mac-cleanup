# Pankaj Mac Cleanup

A small native Mac app for reviewing and clearing a fixed list of rebuildable caches. No AI subscription, web server, third-party runtime, account connection, or background agent is needed.

## Use it

1. Open **Pankaj Mac Cleanup** from your Applications folder or Spotlight.
2. Click **Scan caches**. Scanning does not delete anything.
3. Close the apps you want to clean and pause package installs. Scan again if an item is blocked.
4. Select individual caches. Nothing is selected automatically.
5. Click **Clear selected** and review the confirmation. Clearing permanently deletes those cache folders, bypassing Trash.
6. Review the result and free-space reading. **Show cleanup history** opens the folder containing your local audit log.

Caches rebuild during use, and clearing them can temporarily slow page loading or increase network usage. Keep a current backup of important files. This app only handles its supported cache paths; it does not promise that every byte under macOS “System Data” can be removed.

## Scope and protections

- Supported caches: Chrome, Spotify, Firefox, Comet, pip, npm, Homebrew, Go, node-gyp and TypeScript.
- Exact paths are displayed before cleanup. Browser caches are separate from browser profiles in Application Support.
- The app skips caches associated with running apps or detected package installs, and checks again immediately before deletion. Package process detection is best effort; pause installs yourself too.
- Paths must match a built-in allowlist under the current user's home. Symlinks and symlinked parent paths are rejected.
- Replaced cache directories and substantial growth after scanning require a new scan.
- No administrator commands, scheduled jobs, login items, network requests, analytics or remote uploads.
- Photos, documents, downloads, music, offline-download storage, browser profiles, cookies, passwords, history, system files, snapshots, Trash and active AI-runtime/update caches are outside the deletion allowlist.
- An error can occur partway through filesystem deletion. The result reports such cases as incomplete, and saves outcomes where history is writable.

History is stored locally at `~/Library/Application Support/Pankaj Mac Cleanup/history.jsonl`. The log contains timestamps, cache paths, measured sizes and outcomes. It is not an inventory of individual deleted files. Free-space changes can differ from measured cache sizes because other apps, APFS and macOS also change storage.

## Build from source

Requires macOS 13 or later and Apple's Command Line Tools (Swift compiler). The compiler is needed only to build, not to run the resulting app. No package downloads are used by these scripts.

For an easy rebuild and install, double-click **Install.command** in Finder. It runs the safety tests, builds, installs into your user Applications folder, and opens the app without cleaning anything. Installing Apple's compiler on a Mac that does not already have it can use several GB; the compiled app itself is small.

```sh
bash scripts/test.sh
bash scripts/build.sh
open "build/Pankaj Mac Cleanup.app"
```

To install for your user account:

```sh
mkdir -p "$HOME/Applications"
ditto "build/Pankaj Mac Cleanup.app" "$HOME/Applications/Pankaj Mac Cleanup.app"
xattr -cr "$HOME/Applications/Pankaj Mac Cleanup.app"
codesign --verify --deep --strict "$HOME/Applications/Pankaj Mac Cleanup.app"
```

The build is ad-hoc signed locally; it is not Apple Developer ID signed or notarized. A downloaded build may trigger Gatekeeper. Build locally from source rather than disabling macOS security settings. Binary builds are ignored by Git. Source and any release artifacts contain no personal cleanup records.

For a read-only diagnostic scan in Terminal, run `bash scripts/test.sh --scan-only`. Normal safety tests use temporary fixtures; this optional scan measures the actual current user's supported caches without deleting them.

## Remove it

Move **Pankaj Mac Cleanup.app** to Trash. Optionally remove its history folder using Finder. It installs no background service.

## Inspiration

Inspired by [Kunwar1417/mac-cleanup](https://github.com/Kunwar1417/mac-cleanup), which supplies instructions for an AI cleanup assistant and a demonstration website. This is an independently implemented native app; no upstream source or instruction text is bundled. It deliberately supports a narrower cache-only workflow.

## License

MIT. See [LICENSE](LICENSE).
