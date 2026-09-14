# FuguBench specification

FuguBench outfits a FuguBSD checkout for a coding agent. It installs the
dependencies of a repository, and it makes and removes worktrees. It operates
the learning library, answers the Claude Code hooks, and measures the sessions.
One program holds every verb. It is one packed Perl file that runs on core Perl
v5.34 and carries the Fugu modules that it uses. Every consumer runs the program
through a wrapper shim, so no install step precedes the first `make deps`.

This document is the entry point of the specification. It holds the plan
contract, the ID conventions, and the document tables.

## Plan contract

- Read [DECISIONS.md](DECISIONS.md) before you make a plan.
- A plan must not go against a decision. To go against a decision, propose a
  change to [DECISIONS.md](DECISIONS.md) and get human approval first.
- A plan must cite each unit that it implements and that is not `done`, for
  example `Implements: DEPS-MANIFEST`.
- A plan can exclude a rule from a unit under `Implements:` with `without`, for
  example `Implements: DEPS-MANIFEST without DEPS-MANIFEST-6`.
- A plan must cite each unit that it touches but neither implements nor extends,
  for example `Defers: TRACE-COLUMNS`.
- A plan must cite each `done` unit that it extends, for example
  `Extends: CLI-VERBS`.
- The change that implements a unit, or a part of one, must set the unit state
  in [STATUS.md](STATUS.md) in the same change.

<a id="conventions"></a>

## Conventions

The ID overlay lives in [spec/CLAUDE.md](CLAUDE.md): the unit anchors, the rule
shape, the append-only numbers, the retire procedure, and the citation forms.

## Specification documents

Each document specifies one area of work. The code of a document prefixes the
IDs of its units.

| Code  | Document                   | Area                                             |
| ----- | -------------------------- | ------------------------------------------------ |
| CLI   | [cli.md](cli.md)           | The program: verbs, options, channels, checkout  |
| DEPS  | [deps.md](deps.md)         | Dependencies: manifests, tiers, aliases, digests |
| WT    | [worktree.md](worktree.md) | Worktrees: create, remove, list, clone           |
| WIKI  | [wiki.md](wiki.md)         | The learning library                             |
| HOOK  | [hooks.md](hooks.md)       | The Claude Code hooks                            |
| TRACE | [traces.md](traces.md)     | The session yardstick                            |
| DIST  | [dist.md](dist.md)         | The pack, the release, the shim, and the update  |

## Governance documents

These documents carry no units.

| Document                     | Role                                                  |
| ---------------------------- | ----------------------------------------------------- |
| [DECISIONS.md](DECISIONS.md) | The decisions. A plan must not go against a decision. |
| [ROADMAP.md](ROADMAP.md)     | The schedule of the work.                             |
| [STATUS.md](STATUS.md)       | The implementation register.                          |
