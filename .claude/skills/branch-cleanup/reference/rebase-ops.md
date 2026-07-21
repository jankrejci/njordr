# Rebase Operations

Step-by-step recipes for each rebase operation, used during cleanup
execution (branch-cleanup Phase 5) or when the user requests a specific
operation. All operations drive interactive rebase non-interactively via
`GIT_SEQUENCE_EDITOR`; never use the `reword` action — it opens an editor
that hangs. Always use `edit` + `git commit --amend -m "..."` instead.

In the commands below, `main` denotes the resolved base `$BASE` from the
branch-cleanup skill (default `origin/main`, or a `reviewBase` override);
substitute it.

## Contents
- Edit a commit (modify content in place)
- Split a commit
- Reword a commit
- Move changes between commits
- Reorder commits
- Drop a commit
- Full soft reset (last resort)

## Edit a Commit (modify content in place)

Use when: a commit needs its content changed without splitting. This is the
most common rebase operation for fixing review findings, removing lines,
or adjusting code in a specific commit.

1. Mark the commit for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i main
   ```
2. The rebase pauses at the target commit. The working tree reflects the
   state as of that commit. Make the changes to the file.
3. Stage and amend:
   ```bash
   git add <modified-files>
   git commit --amend --no-edit
   ```
   Use `--amend -m "new message"` if the message also needs updating.
4. Continue:
   ```bash
   git rebase --continue
   ```

To edit multiple commits in one rebase, mark them all with a single sed
command using `-e` flags. The rebase will pause at each one in order.
After amending each, run `git rebase --continue` to advance to the next.

## Split a Commit

Use when: a commit bundles unrelated changes that belong in separate commits.

1. Mark for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i main
   ```
2. Undo the commit but keep changes in working tree:
   ```bash
   git reset HEAD~1
   ```
3. Re-commit in logical groups:
   ```bash
   git add <files-for-group-1> && git commit -m "..."
   git add <files-for-group-2> && git commit -m "..."
   ```
   For partial file splits, use `git add -p <file>` to stage individual hunks.
4. Continue:
   ```bash
   git rebase --continue
   ```

## Reword a Commit

Use when: a commit message is inaccurate or needs updating after fixup folding.

1. Mark for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i main
   ```
2. Amend with new message:
   ```bash
   git commit --amend -m "$(cat <<'EOF'
   module: New commit message

   - updated bullet points
   EOF
   )"
   ```
3. Continue:
   ```bash
   git rebase --continue
   ```

## Move Changes Between Commits

Use when: specific hunks or files belong in a different commit for logical
coherence. A commit may bundle unrelated changes, or a change may have
landed in the wrong commit during development.

1. Mark the source commit for editing:
   ```bash
   GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i main
   ```
2. Extract changes from the commit. For whole files:
   ```bash
   git reset HEAD^ -- <file1> <file2>
   git commit --amend --no-edit
   ```
   For individual hunks within a file:
   ```bash
   git reset HEAD^ -p -- <file>
   git commit --amend --no-edit
   ```
3. Continue rebase: `git rebase --continue`
4. The extracted changes are now uncommitted. Either:
   - Amend them into a later commit with a second edit rebase, or
   - Create a new commit and reorder it into place

## Reorder Commits

Use when: a commit needs to be at a different position in the branch.

1. Show current order: `git log --oneline main..HEAD`
2. Move a commit after a different one:
   ```bash
   GIT_SEQUENCE_EDITOR='bash -c "
     LINE=$(grep \"^pick <HASH_TO_MOVE>\" \"\$1\")
     sed -i \"/^pick <HASH_TO_MOVE>/d\" \"\$1\"
     sed -i \"/^pick <TARGET_HASH>/a\\\\$LINE\" \"\$1\"
   "' git rebase -i main
   ```
3. Handle any conflicts from the new order.

## Drop a Commit

Use when: a commit should be removed entirely.

```bash
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/drop <HASH>/'" git rebase -i main
```

## Full Soft Reset (last resort)

Use when: commits are too interleaved to rebase cleanly. Requires user
confirmation before proceeding.

1. `git reset --soft main`
2. `git reset HEAD -- .`
3. Stage and commit in logical groups using `/commit` skill
4. Verify: `cargo check` for the firmware crate if it changed
