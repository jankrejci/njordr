---
name: branch-cleanup
description: Prepares a branch for merge by collapsing it into small, logical, atomic commits — each change touched once, linear history, no development archaeology. Use before merging to squash fixups and consolidate redundant commits.
disable-model-invocation: true
allowed-tools: Bash, Read, Edit
---

Rebase toolkit for preparing a branch for merge. Default operation analyzes the
full branch for fixups, redundant commits, and commit message quality, then
presents a cleanup plan for user approval. The per-operation rebase recipes
that execute the plan live in [reference/rebase-ops.md](reference/rebase-ops.md).

## Target End-State

The cleaned branch must read as if the work were authored correctly the
first time. Every decision in this skill serves that goal. The five
invariants:

1. **Atomic and logical** — each commit is one self-contained change that
   builds on its own and is reviewable in isolation.
2. **Each change touched once** — no hunk or behavior introduced by one
   branch commit is later modified by another branch commit. Any such pair
   is squashed so the final form appears exactly once. This eliminates
   every "add X" → "fix X" → "tweak X" chain.
3. **Linear** — a straight line rebased on the base ref: no merge commits,
   no branch-in-branch.
4. **No development archaeology** — no `wip`/`fixup!`/`squash!`, no
   "address review", no typo-fix commits, no revert-of-own-work, no
   commit-then-rewrite. History shows authored intent, not the development
   timeline.
5. **Dependency-ordered** — prerequisite changes precede the commits that
   depend on them.

The governing test for any two commits: *would both exist if the branch
were authored cleanly from scratch?* If not, fold them. Granularity is
still a virtue — many small atomic commits beat one large commit — but
only along logical-change boundaries, never along development-time
boundaries.

## Resolve the base

Before analyzing, resolve the base this branch is cleaned against. It
defaults to `origin/main` — the shared upstream, matching the review
base and CI — not the local `main`, which is often stale. A branch
stacked on other in-flight work sets its own base once with
`git config branch.<name>.reviewBase <base-ref>`:

```bash
BASE=$(git config "branch.$(git branch --show-current).reviewBase" || echo origin/main)
```

Report the resolved base. `$BASE` is both the range delimiter and the
rebase target, so cleanup also restacks the branch onto the current
upstream; fetch first if `origin/main` may be stale. Everywhere below,
`main` in a command stands for `$BASE` — substitute it. On a long-lived
or stacked branch this keeps the cleanup scoped to this branch's own
commits instead of sweeping in unrelated authored history that must not be
rewritten.

## Core Technique: GIT_SEQUENCE_EDITOR

All rebase operations use `GIT_SEQUENCE_EDITOR` to avoid interactive editors.
This is the only safe way for an AI agent to perform interactive rebase.

**NEVER use the `reword` action.** It opens an interactive editor which hangs
in non-interactive mode. Always use `edit` + `git commit --amend -m "..."` to
change commit messages.

```bash
# No-op editor for autosquash-only rebases
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash main

# sed for targeted operations on specific commits
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i main

# Multiple commits in a single rebase
GIT_SEQUENCE_EDITOR="sed -i -e 's/^pick <HASH1>/edit <HASH1>/' -e 's/^pick <HASH2>/edit <HASH2>/'" git rebase -i main

# Bash script for complex todo list rewrites like reordering
GIT_SEQUENCE_EDITOR='bash -c "
  LINE=$(grep \"^pick <HASH>\" \"\$1\")
  sed -i \"/^pick <HASH>/d\" \"\$1\"
  sed -i \"/^pick <TARGET_HASH>/a\\\\$LINE\" \"\$1\"
"' git rebase -i main
```

## Pre-flight (before every rebase)

0. Resolve the base (see above): `BASE=$(git config "branch.$(git branch --show-current).reviewBase" || echo origin/main)`
1. Verify clean working tree: `git status`
2. Create timestamped backup: `git branch backup-$(git branch --show-current)-$(date +%s)`
3. Show current commits: `git log --oneline "$BASE"..HEAD`

## Absorb: Automatic Fixup Creation

`git absorb` automates fixup commit creation. Given staged changes, it
determines which prior commit each hunk belongs to and creates `fixup!`
commits automatically. This replaces the manual process of identifying
target commits with `git log` and running `git commit --fixup=<hash>`.

The algorithm uses patch commutation to guarantee fixups will never conflict
during autosquash. Hunks that cannot be unambiguously attributed are left
staged with a warning.

### Usage

```bash
# Stage fixes, then absorb into fixup commits
git add <fixed-files>
git absorb --base "$BASE"

# Preview first without creating commits
git absorb --base "$BASE" --dry-run

# Create fixups and immediately autosquash them
git absorb --base "$BASE" --and-rebase
```

**Always pass `--base "$BASE"`** to search the full branch. The default
search depth is only 10 commits.

### When to use absorb vs manual fixup

| Scenario | Tool |
|----------|------|
| Multiple fixes across files, each attributable to one commit | `git absorb` |
| Fix touches lines not modified by any branch commit | manual `git commit --fixup` or standalone commit |
| New files that have no prior commit to absorb into | manual commit |
| Need to verify target attribution before committing | `git absorb --dry-run`, then manual if unclear |

### Recovery

git-absorb saves `PRE_ABSORB_HEAD` before modifying anything:
```bash
git reset --soft PRE_ABSORB_HEAD
```

## Default Operation: Merge Readiness Cleanup

When invoked without arguments, perform a full analysis of the branch and
present a cleanup plan to the user. Do NOT execute changes until the user
approves the plan.

### Phase 1: Autosquash Fixups

If any `fixup!` or `squash!` commits exist:

```bash
git log --oneline "$BASE"..HEAD | grep -E 'fixup!|squash!'
```

1. Validate each fixup has a matching target commit on the branch
2. Warn if any fixup is orphaned
3. Run autosquash:
   ```bash
   GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash "$BASE"
   ```

If no fixups exist, skip to Phase 2.

### Phase 2: Identify Logical Changes

Analyze the branch by reading every commit's full diff (`git show <hash>`)
and understanding the intent behind each change. The goal is the
**Target End-State** above: each commit is exactly one logical change,
every change appears exactly once, and the history is linear and
dependency-ordered.

The primary test is **touched once**. Build a picture of which commits
modify which lines: `git log -p "$BASE"..HEAD -- <file>` per file, or scan
each `git show <hash>`. Any line, hunk, or behavior that one branch commit
introduces and a *later* branch commit changes is a squash candidate — the
two are the same logical change split across development time.

**What is a logical change?** A single reviewable idea: adding a feature,
fixing a bug, refactoring an API, updating documentation for a specific
reason. A logical change may span many files or touch a single line — file
count is irrelevant.

1. Read every commit with `git show <hash>` and summarize its intent in
   one sentence. Group commits by the logical change they contribute to.

2. Identify commits that should be **squashed** (multiple commits that are
   part of the same logical change):
   - A commit and a later follow-up fix for it (typo, missed case, cleanup).
   - A commit that adds something and a later commit that immediately
     rewrites or supersedes part of it before anyone reviewed it.
   - Incremental refinements to the same idea that have no standalone
     review value. Example: commit A adds a parser, commit B renames a
     variable in that parser. B should fold into A.

3. Identify commits that should be **split** (one commit bundling multiple
   unrelated logical changes):
   - A commit that adds a feature AND refactors an unrelated module.
   - A commit that fixes two independent bugs.
   - A commit where the diff has clearly separable hunks serving different
     purposes.

4. Identify commits that should be **reordered** (logical dependencies
   are out of sequence or related commits are separated by unrelated ones).

5. For each finding, record:
   - The commit hash(es) and subjects
   - The logical change they belong to
   - Recommended action: squash, split, reorder, or keep as-is
   - Why: what makes this one logical change (or not)

### Phase 3: Audit Commit Messages

For every commit on the branch, read the full commit with `git show <hash>`
and check:

1. **Title format**: `module: Imperative verb, capital letter` with max 72 chars
2. **Body explains WHY**: The bullets must explain intent and motivation, not
   enumerate code changes the reviewer can see in the diff
3. **No WHAT bullets**: Flag any bullet that just describes a code change
   without explaining why. Examples of bad bullets:
   - "add X option to module Y" — just restates the diff
   - "update config to use new value" — no motivation given
   - "remove unused import" — fine for a title-only commit, bad as a bullet
     in a multi-line message when it doesn't explain why it was there
4. **Accuracy**: The message must match the actual diff. After fixup folding,
   the diff may have grown beyond what the original message described.

For each commit with issues, record:
- The hash and current message
- What is wrong: missing WHY, inaccurate description, bad format
- Suggested reworded message

### Phase 4: Present Cleanup Plan

Present ALL findings to the user in a structured format:

```
## Fixups
(list of fixups folded, or "none")

## Logical Changes
For each logical change identified on the branch, list:
- Description of the logical change (one sentence)
- Commit(s) that belong to it
- Status: clean, needs squash, needs split, needs reorder

## Commit Message Issues
(for each: hash, problem, suggested fix)

## Proposed Actions
1. Squash X into Y (they are the same logical change: ...)
2. Split Z into two commits (bundles unrelated changes: ...)
3. Reorder A before B (logical dependency)
4. Reword W (fix message)
5. ...

## No Changes Needed
(list commits that are already clean)
```

Wait for user approval before proceeding. The user may approve all, reject
some, or modify the plan.

### Phase 5: Execute Approved Changes

Execute the approved plan using the recipes in
[reference/rebase-ops.md](reference/rebase-ops.md). Order of operations
matters:

1. **Squash/drop** first — reduces the number of commits, making subsequent
   operations simpler and less likely to conflict
2. **Split** next — break bundled commits into separate logical changes
3. **Reorder** — group related commits and fix dependency order
4. **Reword** last — messages should reflect final content

Combine as many edits as possible into a single rebase pass by marking
multiple commits with `-e` flags in one `GIT_SEQUENCE_EDITOR` sed command.

### Phase 6: Final Verification

1. Diff against backup must be empty: `git diff backup-<branch>-<ts>..HEAD`
2. `cargo check` for the firmware crate if it changed
   (`cd firmware/vetroplach && cargo check` inside `nix develop`)
3. Verify the **Target End-State** invariants hold:
   - Linear: `git log --graph --oneline "$BASE"..HEAD` shows no merge
     commits and a single line of descent
   - No archaeology: `git log --oneline "$BASE"..HEAD` shows no `fixup!`,
     `squash!`, `wip`, or `tmp` subjects surviving
   - Touched once: no file is modified across multiple commits without a
     distinct logical reason for each (spot-check with
     `git log --oneline "$BASE"..HEAD -- <file>` on files that appear in
     more than one commit)
4. Show before/after commit list to user
5. If the diff is not empty, something went wrong. Inform the user and
   do NOT delete the backup.

## Rebase Operations

Step-by-step recipes for each operation — edit, split, reword, move,
reorder, drop, and full soft reset — are in
[reference/rebase-ops.md](reference/rebase-ops.md). Read that file when
executing Phase 5 or when the user requests a specific operation.

## Conflict Handling

When a rebase encounters a conflict:

1. **Investigate first**: read the conflict markers and understand both sides.
   Check what the target branch changed:
   ```bash
   git log -p -n 3 "$BASE" -- <conflicting-file>
   ```
2. **Simple conflicts** (few files, clear resolution): resolve the files,
   `git add <resolved-files>`, then `git rebase --continue`.
3. **Complex conflicts** (many files, unclear intent): abort immediately
   with `git rebase --abort` and inform the user. Suggest alternatives
   like soft reset or a different rebase strategy.
4. **NEVER escalate** from a failed rebase to `git reset --hard`,
   `git checkout -- .`, or other destructive commands. The only safe
   escape from a stuck rebase is `git rebase --abort`.

## Rules

- NEVER push to remote
- NEVER delete backup branch automatically
- NEVER use destructive commands (`reset --hard`, `checkout -- .`, `clean -f`)
- ALWAYS create backup branch before any rebase
- ALWAYS run `cargo check` for the firmware crate after rebase completes if it changed
- ALWAYS show before/after commit list to user
- ALWAYS abort rebase on unexpected conflicts rather than guessing

## Principles

- One logical change per commit — the unit of review is an idea, not a file
- Touching the same file is not redundancy; serving the same purpose is
- Touching different files is not independence; different intent is
- Keep a commit only if it would exist in a clean-authored branch; fold any
  commit that revises what an earlier branch commit introduced
- Split along logical-change boundaries, never development-time boundaries
- More granular commits are easier to review than large ones, but only
  when each stands as its own logical change
- Analysis is free, action requires approval
- Present the full picture before touching history
- Separate CLAUDE.md changes from code commits
- When in doubt, abort and ask the user
