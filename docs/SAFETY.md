# Safety and privacy

This utility performs filesystem mutations. Its protections are deliberately narrow and reviewable, rather than a promise that cleanup is risk-free.

## Cache cleanup

Only paths listed in `CleanupCore.specs` are eligible for permanent deletion. The app displays each exact path and measured size, starts with no selection, and requires confirmation.

Before clearing an entry, the core checks the allowlist, path containment, symlink resolution, associated processes, directory identity, and size growth since scanning. It refuses a cache that has grown by more than the larger of 1 MiB or 5% since the scan.

Selected cache directories are removed permanently using FileManager. This bypasses Trash. Browser profiles, cookies, saved passwords, and personal downloads are outside the cache allowlist.

Process matching is best effort. It cannot detect every tool that might use a cache, and may produce false positives. Pause package installs and close associated apps before cleaning.

## Personal files

Review mode accepts local Documents, Downloads, or Desktop folders and their subfolders. It reads metadata and lists eligible regular files, not whole folders. Symlinks, aliases, hidden paths, package directories, selected dependency directories, and iCloud items reported by macOS are excluded.

Each file requires a separate confirmation with its full path, size, and modified date. Immediately before moving, the app rechecks its scope, cloud status, filesystem identity, size, and modification date. It uses macOS FileManager's Trash operation, never permanent file deletion, for review-mode items.

Third-party sync services can manage ordinary local folders without an iCloud flag. The app cannot reliably detect all such folders. Moving a synced file may affect other devices; avoid reviewing sync-managed folders here.

## Boundaries and limitations

- Validation and removal are separate filesystem operations. They are not atomic and do not eliminate time-of-check/time-of-use races. Avoid concurrent changes to the files or directories being reviewed.
- Cache measurement uses allocated disk usage; file review shows file lengths. APFS clones, compression, snapshots, and concurrent activity can make actual reclaimed space differ.
- A deletion error can occur after some cache files have already been removed. Results identify incomplete outcomes where possible.
- Backup checks report the latest accessible Time Machine backup. They do not verify its completeness, restorability, or coverage of a particular file.
- History writes can fail after a successful removal or move. The app reports that failure separately; the log is not a transactional recovery system.
- Tests inject a temporary-directory move implementation. They verify application logic without touching the real Trash; OS Trash integration and dialogs require manual checks.
- Tests have run on Apple Silicon. Intel source compatibility has not been validated on Intel hardware. Release builds are ad-hoc signed and not notarized.

## Data handling

The app contains no networking, analytics, remote uploads, scheduled cleanup, login item, or background daemon. It requests no administrator access. It invokes local macOS utilities to measure caches, inspect processes and free space, and query Time Machine.

Process arguments are inspected locally to detect package tools. They are not displayed or recorded in cleanup history. File-review scans inspect metadata rather than reading document contents.

Local history includes file paths, which can reveal private filenames. Do not upload history, unredacted screenshots, or personal directory listings to public issues. Source and release artifacts must not include those records.

See [SECURITY.md](../SECURITY.md) for private vulnerability reporting.
