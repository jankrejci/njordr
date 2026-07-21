# CI stage groups. Each is a linkFarm over a slice of the flake's
# `checks`, so `nix build .#ci-<stage>` builds exactly that slice and
# nothing else — the GitHub Actions pipeline runs these and a developer
# runs the identical command locally. No shell wrapper sits between CI
# and nix.
#
# `classify` maps every check name to exactly one stage, so the three
# groups partition `checks` with no overlap and no gaps: the union of
# ci-format + ci-clippy + ci-check is precisely `nix flake check`.
# ci-format is the formatting gate, ci-clippy the clippy gate, and
# ci-check the remainder — the firmware release build and the PCB
# DRC/ERC gates. A newly added check that matches neither the format set
# nor the `clippy-` prefix falls into ci-check, so coverage can never
# silently shrink. Run a single check with
# `nix build .#checks.<system>.<name>`.
{ pkgs, checks }:
let
  classify =
    name:
    if
      builtins.elem name [
        "fmt"
        "nixfmt"
      ]
    then
      "ci-format"
    else if pkgs.lib.hasPrefix "clippy-" name then
      "ci-clippy"
    else
      "ci-check";
  grouped = pkgs.lib.groupBy classify (builtins.attrNames checks);
  farm = stage: pkgs.linkFarmFromDrvs stage (map (name: checks.${name}) (grouped.${stage} or [ ]));
in
{
  ci-format = farm "ci-format";
  ci-clippy = farm "ci-clippy";
  ci-check = farm "ci-check";
}
