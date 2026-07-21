---
name: commit
description: Creates atomic git commits with chunk-based staging and the gitlint-gated message format. Use when committing staged or unstaged changes, or when the user asks to commit or to split work into commits.
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
---

Create atomic commits for staged/unstaged changes using chunk-based staging.

## Commit Format

Commit messages are gated by `gitlint` in the CI `commits` job; `.gitlint` and
`.gitlint-rules/` are the enforced source of truth. This skill is the
authoritative description of that format.

```
module: High-level what in imperative style

- why this change was needed
- why this approach, if non-obvious
```

**Philosophy:** the diff shows WHAT changed; the message explains WHY.

**Title rules:**
- Match `^\.?[a-z][a-z0-9-]+(: [a-z][a-z0-9-]+)*: [A-Z]`: one or more
  lowercase `module:` prefixes, then a capital first word, imperative,
  max 72 chars (e.g. `ci:`, `pcb:`, `firmware:`, `flake:`,
  `sensor-board:`, `vetroplach-board:`)
- Module is the subproject/area, not a list of files
- The prefix must not be `fix`, `fixup`, `wip`, or `tmp` (rule UC3)
- No issue-tracker tag (`#VETRO-71` or `#71`) in the title; put the
  ticket reference in the body (rule UC4)

**Body rules:**
- Each line is blank, a `- ` bullet, or a `  ` indented continuation
  (rule UC1); max 72 chars/line (rule B1)
- Start bullets lowercase; this is convention, not gitlint-enforced
- Wrap long lines with `par w72p2h1` (greedy fill, 2-char hanging indent)
- Answer WHY: motivation, problem solved, approach rationale
- NO restating the diff, NO signatures
- NO `Co-Authored-By` or `Signed-off-by` lines, NO emojis (rule UC2)

**Bad vs good:**
```
BAD:  "- add StandardOutput directive to the service file"
GOOD: "- prometheus must reach the service over the network"
```

## Process

1. Run `git status` and `git diff` to understand all changes
2. Run `git log -5 --oneline` to see recent commit style
3. Identify logical groups of changes that belong together
4. For each logical group:
   - Stage specific chunks with `git add -p <file>` for modified files
   - For new files: `git add -N <file> && git add -p <file>`
   - Verify staged changes: `git diff --cached`
   - Run `cargo check` in the affected crate directory (skip if no Rust changes)
   - Create commit using HEREDOC:
     ```bash
     git commit -m "$(cat <<'EOF'
     module: Title here

     - why this change was needed
     - why this approach if non-obvious
     EOF
     )"
     ```
5. Run `git log --oneline -5` to verify

## Fixup Commits

For iterations after review feedback, use fixup commits:
```bash
git commit --fixup=HEAD
```

Or target a specific commit:
```bash
git commit --fixup=<commit-hash>
```

Fixups will be squashed later with `/branch-cleanup`.

## Chunk Staging Reference

Interactive patch mode (`git add -p`) commands:
- `y` - stage this hunk
- `n` - skip this hunk
- `s` - split into smaller hunks
- `q` - quit, do not stage remaining hunks

## Rules

- One logical change per commit, reviewable in isolation
- Separate unrelated changes into different commits
- The affected crate builds via its `nix develop` shell (skip if no Rust
  changed): `cd firmware/vetroplach && cargo check` inside `nix develop`

**Commit separation — do not bundle these with source code:**
- `Cargo.toml` + `Cargo.lock` (dependency changes) get their own commit,
  placed before the code that uses them
- Generated/maintained assets get their own commit
- Lock files (`Cargo.lock`, `flake.lock`) and AI config (`.claude/`,
  `CLAUDE.md`) get separate commits, never bundled with source or with
  each other
- Exception: bundle when separation would leave either commit unable to
  build — the initial introduction of a new crate, or a pure rename where
  source and lockfile must move together

**Never:**
- NEVER push to remote
- NEVER use --amend unless explicitly requested
- NEVER skip cargo check when Rust code changed
- NEVER add Co-Authored-By or any other signature/trailer to commit messages
