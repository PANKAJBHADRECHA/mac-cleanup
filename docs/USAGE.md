# Usage guide

Practical steps for cache cleanup and individual file review. For installation and development, see the [README](../README.md).

## Use it

1. Open **Pankaj Mac Cleanup** from your Applications folder or Spotlight.
2. Select **Quick clean · Caches**, then click **Scan caches**. Scanning does not delete anything.
3. Close the apps you want to clean and pause package installs. Scan again if an item is blocked.
4. Select individual caches. Nothing is selected automatically.
5. Click **Clear selected** and review the confirmation. Clearing permanently deletes those cache folders, bypassing Trash.
6. Review the result and free-space reading. **Show cleanup history** opens the folder containing your local audit log.

Caches rebuild during use, and clearing them can temporarily slow page loading or increase network usage. Keep a current backup of important files. This app only handles its supported cache paths; it does not promise that every byte under macOS “System Data” can be removed.

## Review documents and downloads

1. Select **Review files · Documents**.
2. Click **Choose folder**. The app checks the latest accessible Time Machine backup. If it cannot verify a backup, or the backup is older than a week, it asks whether to continue. It does not create a backup or change Time Machine settings.
3. Choose a **local** Documents, Downloads or Desktop folder, or a subfolder inside one. Nothing is scanned outside the chosen folder.
4. Choose **All sizes**, **10 MB+**, **100 MB+** or **1 GB+**. Results show the largest files first, with size, modified date and full path. **10 MB+** is the default.
5. Click **Show in Finder**, then press Space to preview a file.
6. Click that file’s **Move to Trash** button. Review its exact path and confirm. Every file needs its own confirmation; there is no bulk personal-file deletion.
7. Restore a file with Finder’s **Trash → Put Back** if needed. Moving to Trash does not free space. Empty Trash yourself only when you are sure. The app never empties it.

Review scans read metadata, not document contents. Hidden folders, package directories (including app and photo libraries), symbolic links, aliases, iCloud files reported by macOS, and dependency folders such as node_modules are skipped. Third-party sync tools can sync ordinary local folders without an iCloud flag; avoid choosing folders managed by them if you do not want synced changes. iCloud-backed Documents or Desktop may be unavailable; use Finder to manage those files instead.

Results are limited to the 500 largest matches and scanning stops after 100,000 directory entries. Partial results and unreadable or excluded items are reported. Choose a smaller subfolder for more detail. Files are rechecked for path, cloud status, filesystem identity, size and modification date before moving. A changed or replaced file requires another scan. Recent files are marked for extra care.

macOS may ask for access to the folder you choose. No Screen Recording, Accessibility or administrator permission is required. Review mode handles files only, not whole folders, iPhone backups, Docker images or deleted-app leftovers.

## Scope and protections

- Supported caches: Chrome, Spotify, Firefox, Comet, pip, npm, Homebrew, Go, node-gyp and TypeScript.
- Exact paths are displayed before cleanup. Browser caches are separate from browser profiles in Application Support.
- The app skips caches associated with running apps or detected package installs, and checks again immediately before deletion. Package process detection is best effort; pause installs yourself too.
- Paths must match a built-in allowlist under the current user's home. Symlinks and symlinked parent paths are rejected.
- Replaced cache directories and substantial growth after scanning require a new scan.
- No administrator commands, scheduled jobs, login items, network requests, analytics or remote uploads.
- Personal files are outside the permanent cache-deletion allowlist. Review mode can move individual confirmed files from the chosen local Documents, Downloads or Desktop folder to Trash.
- Photos libraries, music libraries, offline-download storage, browser profiles, cookies, passwords, history, system files, snapshots, emptying Trash and active AI-runtime/update caches remain outside this tool's cleanup scope.
- An error can occur partway through filesystem deletion. The result reports such cases as incomplete, and saves outcomes where history is writable.

History is stored locally in `~/Library/Application Support/Pankaj Mac Cleanup/`. `history.jsonl` contains cache events; `files-history.jsonl` records each file moved to Trash, its original and resulting paths, size and timestamp. Cache history is not an inventory of individual deleted cache files. Logs are never uploaded. The file-review view reports items moved during the current app session; history retains previous sessions. Free-space changes can differ from measured cache sizes because other apps, APFS and macOS also change storage. Trash moves are not counted as space reclaimed.

## Troubleshooting

- **A cache is blocked:** Quit the associated app and helpers, pause package installs, and scan again. Process matching is conservative and may block an item unnecessarily.
- **A file changed after scanning:** Scan again and review its current details.
- **A folder cannot be read:** Choose it again and review any macOS access prompt.
- **A cleanup was incomplete:** Some cache files may already have been removed. Review the outcome and scan again; cleanup is not atomic.
- **The downloaded app is blocked:** Build locally from source. The project does not distribute a notarized build.

## Uninstall

Quit the app and move **Pankaj Mac Cleanup.app** to Trash. Optionally remove its history folder using Finder. It installs no background service.
