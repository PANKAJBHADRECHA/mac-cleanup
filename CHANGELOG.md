# Changelog

## Unreleased

- Reorganize public documentation into a concise README, usage guide, safety notes, and contribution guidance.
- Provide a macOS CI template for tests, build, and signature verification; activation requires workflow write permission.
- Add structured bug reports and private security reporting guidance.

## 1.1.0 — 2026-11-22

- Add local-file review with size filters, modification dates, and Finder reveal actions.
- Require individual confirmation before moving a file to macOS Trash.
- Check accessible Time Machine backup status before folder selection.
- Exclude protected paths and recheck file identity and metadata before moving.
- Record file moves locally and distinguish items in Trash from reclaimed space.
- Add 23 file-review checks alongside the existing 17 cache checks.

## 1.0.0 — 2026-11-22

- Introduce native SwiftUI cache review with explicit selection and confirmation.
- Add a fixed cache allowlist, running-process checks, symlink rejection, and stale-directory validation.
- Record local cleanup outcomes and show before/after available storage.
- Add direct Swift build/test scripts and a local installer.
