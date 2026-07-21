---
name: fix-review
description: Applies /review-branch findings as conflict-safe fixup commits or rebase edits. Use after a branch review to address the reported findings.
disable-model-invocation: true
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

Apply fixes from `/review-branch` findings passed in `$ARGUMENTS`.

In the commands below, `main` denotes the resolved review base `$BASE`
(default `origin/main`, or a `branch.<name>.reviewBase` override);
substitute it.

## Process

1. Parse findings from arguments (categorized items with file:line references)
2. Classify each finding: code fix, structural fix, documentation-hardening,
   or documented-no-change (with rationale). Every finding must be
   addressed — nothing is skipped. A finding that turns out to be a false
   positive or a reviewer misunderstanding is NOT dismissed: the code's own
   comments or docs were unclear enough to mislead the review, so harden
   that documentation instead, so the next review round does not re-raise
   it. "The reviewer was wrong" is itself a finding against the docs.
3. Present the full list to user with proposed action for each item
4. Wait for user approval
5. Apply all approved fixes

### Fix classification

**Code fixes** (apply via fixup commit): the finding requires changing file
content but the commit structure is correct. Examples: remove duplicate line,
fix typo, add missing check, change a value.

**Structural fixes** (apply via rebase edit): the finding requires changing
commit boundaries. Examples: split a commit, move files between commits,
remove a file from the wrong commit. Use the patterns from `/branch-cleanup`.

**Documentation-hardening** (apply via fixup commit): the finding is a
false positive or a reviewer misunderstanding, but the misread was
possible because a comment, doc, or rationale was missing, incomplete, or
contradicted by nearby text. Do not just record "false positive" — add or
correct the documentation that would have prevented the misread (for
example: note that a script's imports come from the dev shell, or state
why a divisor deliberately diverges from the sibling driver). The goal is
that the same finding does not resurface next review round.

**Documented-no-change**: the finding is acknowledged but no code, doc, or
commit-boundary change is warranted — for example, the deviation is
already justified in the existing commit body and the existing comments
already make it clear. Reserve this for cases where nothing in the tree
could be improved to forestall the finding; if the review could have been
avoided by clearer docs, prefer documentation-hardening. Record the
rationale in the final summary; do not silently drop the item.

### For each code fix:

#### Step 1: Identify the target commit

Find the commit that introduced the issue:
```bash
git log --oneline main..HEAD -- <file>
```

#### Step 2: Conflict prevention check

Before creating a fixup, verify the fix will not conflict during autosquash:

1. Read the target commit's diff for the file: `git show <hash> -- <file>`
2. Verify the issue exists in lines modified by the target commit
3. Check if later commits also modified the same lines:
   ```bash
   git log --oneline <hash>..HEAD -- <file>
   ```
   If later commits touched the same lines, fixup the **latest** commit
   that modified those lines instead of the original
4. If no commit cleanly owns the lines, create a standalone commit instead

#### Step 3: Apply minimal fix

- Read the file and understand the problem
- Apply the minimal fix for this specific finding
- Do NOT introduce new changes unrelated to the finding
- Stage only the fixed file

#### Step 4: Verify staged changes

1. Run `git diff --cached` and confirm the staged changes only touch
   sections relevant to the finding
2. Run `cargo check` for the affected crate

#### Step 5: Create fixup commit

**Multiple code fixes**: if several fixes are ready and each touches lines
clearly owned by a single prior commit, apply all fixes, stage them, and use
`git absorb --base main` to create all fixup commits at once. Use
`--dry-run` first to verify attribution. This replaces steps 1-4 per fix.

**Single fix or ambiguous attribution**: create the fixup manually:
```bash
git commit --fixup=<target-hash>
```

If conflict was unavoidable in step 2, create a standalone commit instead:
```bash
git commit -m "module: Fix description"
```

### For each structural fix:

#### Step 1: Create backup

```bash
git branch backup-$(git branch --show-current)-$(date +%s)
```

#### Step 2: Apply the rebase operation

Use the appropriate pattern from `/branch-cleanup`:

**Split a commit:**
```bash
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i main
git reset HEAD~1
git add <files-for-group-1> && git commit -m "..."
git add <files-for-group-2> && git commit -m "..."
git rebase --continue
```

**Edit a commit in place** (modify content of a specific commit):
```bash
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i main
# make changes to the file
git add <modified-files>
git commit --amend --no-edit
git rebase --continue
```

**Reword a commit message** (fix inaccurate or incomplete message):
```bash
GIT_SEQUENCE_EDITOR="sed -i 's/^pick <HASH>/edit <HASH>/'" git rebase -i main
git commit --amend -m "$(cat <<'EOF'
module: Updated commit message

- corrected or added bullets
EOF
)"
git rebase --continue
```

NEVER use the `reword` action. It opens an interactive editor which hangs in
non-interactive mode. Always use `edit` + `git commit --amend -m "..."`.

**Multiple operations**: mark all target commits for edit in a single sed
command with `-e` flags. The rebase pauses at each in order.

#### Step 3: Verify

1. Run `cargo check` for affected crates
2. If a backup exists from before the structural fix, verify
   `git diff backup-<branch>-<ts>..HEAD` shows only the intended changes

### After all fixes are applied

Show a summary of what was done:
```
## Fixes Applied

fixup! <target-msg> -- fixed <description>
fixup! <target-msg> -- docs-harden: <what was clarified> (was false positive)
rebase-edit <target-msg> -- <description>
standalone: <msg> -- <description> (conflict avoidance)
documented: <description> -- <rationale, no change made>
```

## Rules

- Every finding must be addressed — never silently skip. Fix it, harden
  the documentation that allowed the misread (for false positives), or
  explicitly document why the existing state is acceptable and could not
  be made clearer.
- One logical fix per fixup commit
- Never batch unrelated fixes into a single commit
- Never introduce changes beyond what the finding requires
- Follow commit rules from `CLAUDE.md`
- NEVER push to remote
- NEVER skip `cargo check` when Rust code changed
- If a rebase conflicts, abort with `git rebase --abort` and inform the user
