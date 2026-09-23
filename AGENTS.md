# Rules for coding agents in this repo

Codex reads this file. Claude Code reads `CLAUDE.md`, which points here. **The
same rules apply to both**, because both work in the same folder on Oren's
machine — and on 2026-09-23 one agent pushed straight to `main` from a branch
the other had created, shipping unreviewed work before its checks finished.

## Git workflow — every change, every time

1. **Start from `main`.** Run `git status` first. Then
   `git checkout main && git pull`.
2. **If `git status` shows changes you did not make, stop.** Another agent or
   Oren may be mid-change in this folder. Do not commit them, stash them or
   discard them — say what you found and ask.
3. **Make your own branch** for the change. Codex uses `codex/<short-name>`.
   Never commit on a branch you did not create.
4. **Commit, push that branch, and open a pull request into `main`.**
   **Never push directly to `main`.**
5. **Do not merge until CI passes.** The `Screenshots` job can show green even
   when UI tests fail, because it is allowed to fail without failing the run.
   Open that job and check its **Exercise everyday flows** step too.
6. Merge only when Oren has asked for it.

## Why CI is the only word that counts

Development is on Windows with no Swift toolchain. **Nothing Swift compiles on
this machine**, so the macOS CI job is the only compiler, and the installable
app Oren puts on his phone is built from `main`. A broken `main` means no app.

- Never say Swift code works before CI is green on it.
- Before pushing Swift, run `python scripts/brace-scan.py <changed files>`. It
  catches the missing-brace mistakes that otherwise cost a 25-minute CI run.

## Everything else

The architecture, conventions and the list of bugs not to reintroduce are in
`CLAUDE.md`. Read its "Bugs already found and fixed" section before writing
SwiftUI colours, and its note on keeping Settings short before adding a
section anywhere.
