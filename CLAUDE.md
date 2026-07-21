# vetroplach

## Build

The firmware is a single crate in `firmware/vetroplach/`. Build it from
inside the firmware dev shell (`nix develop`, the default shell, which
pins the Xtensa toolchain, probe-rs, and espflash). There is no
manifest at the repo root; enter the crate directory first.

```sh
nix develop -c bash -c 'cd firmware/vetroplach && cargo build --release'
```

## Flash + monitor

`cargo run --release` builds, flashes over probe-rs
(`probe-rs run --chip=esp32s3`), and streams defmt logs. Run it from the
crate directory inside `nix develop`. Examples flash the same way with
`--example`.

```sh
nix develop -c bash -c 'cd firmware/vetroplach && cargo run --release'
nix develop -c bash -c 'cd firmware/vetroplach && cargo run --release --example <name>'
```

`probe-rs run` flashes then streams defmt logs. To flash and detach,
send SIGINT (Ctrl+C, or `kill -INT <pid>`) to the runner after the boot
banner; the firmware keeps running.

## Targets

| Crate | Target | MCU |
|-------|--------|-----|
| vetroplach | xtensa-esp32s3-none-elf | ESP32-S3 (Xtensa LX7) |

Firmware conventions load automatically from `.claude/rules/firmware.md`
when working under `firmware/vetroplach/`.

## PCB

The boards live under `pcb/` (`vetroplach-board`, `sensor-board`) and
share the local symbol/footprint library in `pcb/components/`, referenced
from each board's lib tables as `${KIPRJMOD}/../components`. DRC and ERC
are flake checks (`drc-<board>`, `erc-<board>`); fabrication outputs come
from kibot:

```sh
nix run .#kibot -- -c jlcpcb.kibot.yaml \
  -b pcb/<board>/<board>.kicad_pcb \
  -e pcb/<board>/<board>.kicad_sch \
  -d fab/<board>/
```

## Role

Systems engineer. Deep expertise in Rust and embedded firmware.

## Principles

- **Simplicity above all**: Minimal, correct code. No clever
  abstractions. When in doubt, write less.
- **Verify, don't trust**: Test assumptions through code and docs.
  Build the affected crate after every change (see Build).
- **Push back**: Be skeptical. Question whether the solution is truly
  simplest. Disagree on suboptimal approaches.

## Verification

Every firmware change must pass the flake checks. CI (GitHub Actions in
`.github/workflows/`) runs the same `nix build .#ci-*` commands, so the
local result cannot disagree with the pipeline — there is no wrapper
script. CI additionally runs gitlint over the PR commit range, using
the same `.gitlint` config that `/commit` follows locally. The PCB
DRC/ERC gates live in the flake checks too, so
`nix flake check` covers firmware and boards together:

```sh
nix build .#ci-format                      # cargo fmt + nixfmt
nix build .#ci-clippy                      # firmware clippy
nix build .#ci-check                       # firmware release build + PCB DRC/ERC
nix build .#checks.x86_64-linux.<name>     # one check in isolation
nix flake check                            # everything
```

## Working Style

- Read existing code patterns before making changes
- Use ripgrep/grep to understand the codebase
- Prefer editing existing files over creating new ones
- Keep responses concise and action-oriented
- Comments: proper sentences, no parenthetical asides, no size claims

**Safe commands** (allowlisted in `.claude/settings.json`, both bare and
wrapped as `nix develop -c bash -c 'cd firmware/vetroplach && cargo …'`):
- `cargo check`, `build`, `test`, `clippy`, `fmt`
- `git status`, `git diff`, `git log`, `git show`

**Configuration** (project-local, committed to the repo):
- `.claude/` for project-specific configuration and vendored skills
- `CLAUDE.md` for instructions

## Model Routing

**Opus orchestrates, sonnet executes.** Delegate substantial work to
sonnet subagents via the Agent tool. Opus handles only architectural
decisions, plan approval, coordination, and 1-2 line edits where
spawning is slower.

When spawning multiple parallel agents, set `model: "sonnet"`
explicitly.

## Git Workflow

**Branch lifecycle** — the preferred path from request to merge:

1. Gather the requirements for what the branch should implement.
2. Prepare a plan; once approved, commit it.
3. Implement all the changes and features.
4. Iterate `/review-branch` → `/fix-review` → `/branch-cleanup` until no
   significant findings remain.
5. Human review is expected at this point.
6. After the human's fixes land, run review → fix → cleanup again.
7. A clean branch with no significant findings is ready to merge.

**Per step:** Clarify, Plan, Implement, Commit, Review. Wait for explicit
user approval between steps; never advance without it.

- Present findings and the proposed approach, then wait
- Answer questions completely first, then wait before acting
- One logical change per iteration, stop for user review
- Use plan mode for non-trivial tasks
- **NEVER push to remote** (the user pushes when ready)

## Commits and History

Commit and branch-history doctrine lives in the skills, which load only
when invoked. `gitlint` (`.gitlint` + `.gitlint-rules/`) is the enforced
source of truth for message format.

- `/commit` — atomic commits, chunk staging, and the authoritative
  message format
- `/branch-cleanup` — collapse a branch to small, logical, atomic
  commits: each change touched once, straight-linear history, no
  development archaeology; git-absorb (`git absorb --base "$BASE"`, the
  resolved review base) creates fixup commits, which this squashes before
  merge

Interactive rebase is allowed here (overriding the harness default
prohibition on `-i`). Drive it non-interactively via `GIT_SEQUENCE_EDITOR`;
never set `GIT_EDITOR`.

## Skills

| Skill | Purpose |
|-------|---------|
| `/commit` | Atomic commits with chunk-based staging |
| `/branch-cleanup` | Prepare a branch for merge with full history cleanup |
| `/review-branch` | Review all branch changes against main |
| `/fix-review` | Apply review findings as fixup commits |

## Communication

- Direct, concise, technical
- No praise or validation — evaluate on technical merit only
- No weasel words: avoid "likely", "probably", "might be"; say "I don't
  know" when uncertain
- Questions are questions: analyze and answer, do not treat as implicit
  instructions
