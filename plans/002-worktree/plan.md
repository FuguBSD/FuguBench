# 002 — The worktree verb

## Status

Proposed. It lands after plan 001, the program, and it waits on nothing else.
The Workspace swaps its make targets and its bootstrap recipe to the verb in a
plan of its own. That plan follows this one.

Implements: WT-CREATE. Implements: WT-REMOVE. Implements: WT-LIST. Implements:
WT-CLONE. Implements: WT-SAFETY.

Implements: CLI-VERBS. Implements: CLI-SANDBOX. This plan adds the `worktree`
row of the verb table and of the sandbox table. Both units stay `partial` until
the last verb lands.

Implements: CLI-CONFORMANCE without CLI-CONFORMANCE-2. This plan ports the
Workspace test `t/ci/worktree.t`. The tests of `wiki.pl` and `traces.pl` come
with their verbs. The dry-run trace comes with the dependency installer. The
unit stays `partial` until then. The first of plans 002, 003, and 005 to land
rewords CLI-CONFORMANCE-1, and the later two point at the landed text.

## Purpose

The Workspace script `scripts/worktree.pl` is the design source of every WT
unit, and the specification was written from it. This plan moves that behavior
into one verb of `fugubench`, so the hooks and the make targets of every
consumer call one program. The ported test keeps each behavior that the script
asserts.

## Scope

In scope:

- The verb module `App::FuguBench::Worktree` with the subcommands `create`,
  `remove`, `list`, and `clone`.
- The `worktree` row of the verb table and of the sandbox table.
- The group form of `$app->command`, which create needs for its cleanup.
- The port of the Workspace test, and the tests of the create, the remove, and
  the clone cases that the port does not cover.

Out of scope:

- The `WorktreeCreate` hook entry. It lands with the hook verb.
- The Workspace make targets `worktree`, `worktree-remove`, `worktree-list`, and
  the `bootstrap` recipe. A Workspace plan swaps them to the verb.

## Constraints that shape the design

**The root is the main checkout.** `-C <dir>` names the main checkout, as
`worktree.pl -C` does, and the checkout walk of CLI-CHECKOUT finds its
`.toolingrc`. A linked worktree holds a `.git` file, not a directory. The verb
refuses such a root with a failure, so no worktree nests under another one.

**The base resolves against the root.** The base is the `worktree.base` key,
with the default `.claude/worktrees`. A clone under `Projects/` can inherit the
key from the workspace file, and its worktrees still belong to the clone. So the
value resolves against the root, not against the home of the key. Plan 001 lands
that anchor in CLI-CONFIG-2, so this plan changes no rule of CLI-CONFIG.

**The pid of a running child.** `Fugu::Process->run` keeps the pid of its child
private until the child exits, so a signal handler cannot reach the group.
`$app->command` gains the argument `group => 1`. In that form the child starts
through `Fugu::Process->spawn_command` with `daemonize`, so it leads its own
session. The child gets one handle for both streams, on one file in the
temporary directory. The dispatcher keeps the pid in `child` while it waits, and
it writes the file to standard error after the exit. The signal handler of
create calls `Fugu::Process->terminate($app->child, group => 1)`. A `run` that
reports the pid to its caller is follow-on work of Fugu, and the group form then
shrinks to one flag.

**The cleanup of create runs every step.** The steps are the worktree removal,
the directory removal, the branch deletion, `git worktree prune`, and the parent
prune. A step that fails does not stop the next one. The signal handler ignores
further signals, stops the group, waits, runs the cleanup, and exits 1.

**The shape checks come from the script.** A name starts with a letter or a
digit, and a `..` anywhere fails. A path starts with a letter, a digit, a dot,
or an underscore. A first character of `-` would reach git as an option. The
implementation adds the first-character rule to WT-CREATE-2 and to WT-CLONE-5
with the code.

**The list line has one shape.** The ported test matches
`^<name>\s+\d+ d\s+<state>`, so the line is `%-40s %4s d  %s`: the name, the
age, and the state. An unreadable `.git` file gives the age `?`. The
implementation adds the line shape to WT-LIST-1 with the code.

**The port changes more than the invocation.** The fixture of the test gains an
empty `.toolingrc`, because the checkout walk stops without one. The assertion
on `mk/local.mk` goes, because it tests a file of the Workspace, and the
Workspace test keeps it. Every other line stays. The implementation rewords
CLI-CONFORMANCE-1 with the code. The new text: "with the invocation and the
fixture changed, and nothing else". It adds: "an assertion on a file of the
Workspace stays in the Workspace test".

**The sandbox row is pledge-only.** Create, remove, and clone pledge
`stdio rpath wpath cpath fattr proc exec`. List pledges `stdio rpath proc exec`.
The bootstrap `make` runs a tool set that no row can enumerate. So the row
unveils nothing, as plan 001 states for a verb with a child. The current
directory of a bootstrap sits under the base, so clone writes inside the root.

## The interface contract

### The verb

`App::FuguBench::Worktree->command` returns the entry of the verb table. The
usage is `<subcommand> [--force] [<name> | <path>...]`, and the one option is
`force`. The body reads the subcommand as its first argument. An unknown
subcommand, a missing argument, and an extra argument each give a usage error.
The differences from `worktree.pl` are the invocation,
`bin/fugubench -C <root> worktree <sub>`, and the configurable base.

| Subcommand                | Result line                              | Exit codes                                                                                |
| ------------------------- | ---------------------------------------- | ----------------------------------------------------------------------------------------- |
| `create <name>`           | The worktree path, as the only line      | 0; 1 a bad name, a nest, an existing directory, a failed step, a signal; 2; 3 a bad base  |
| `remove [--force] <name>` | None                                     | 0; 1 a bad name, a refusal, a path outside the base, a branch that stays; 2; 3 a bad base |
| `list`                    | One line per worktree, or `no worktrees` | 0; 2; 3 a bad base                                                                        |
| `clone <path>...`         | None                                     | 0; 1 a bad path, an unreadable source, a failed clone or copy; 2                          |

Every message goes to standard error: each risk line of a refusal,
`git refused, deleting the directory`, `already exists, skipped: <dst>`,
`copied <src> -> <dst>`, `missing in main checkout, skipped: <path>`, and
`already the main checkout, nothing to do`. A risk line is
`<rel>: uncommitted change` or `<rel>: <n> commit(s) that no remote holds`, and
`<rel>` is `.` for the worktree itself.

Each child runs through `$app->command`. Create passes `group => 1` for its
three children: `git branch`, `git worktree add`, and `make`.

### The dispatcher

`command(\@cmd, group => 1)` runs the child as the leader of its own session. It
keeps the pid in `child` while it waits. After the exit it writes the output of
the child to standard error, and it returns as the plain form does.

`child` returns the pid of the running child of the group form, or undef.

## Files

| File                             | Change                                             |
| -------------------------------- | -------------------------------------------------- |
| `lib/App/FuguBench/Worktree.pm`  | New: the verb and its four subcommands             |
| `lib/App/FuguBench/Worktree.pod` | New: the contract                                  |
| `lib/App/FuguBench.pm`           | The verb row, the sandbox row, and the group form  |
| `lib/App/FuguBench.pod`          | The group form and `child`                         |
| `t/fugubench/worktree.t`         | New: the port of Workspace `t/ci/worktree.t`       |
| `t/fugubench/worktree-verb.t`    | New: the create, the remove, and the clone cases   |
| `spec/cli.md`                    | The rewording of CLI-CONFORMANCE-1                 |
| `spec/worktree.md`               | The first-character rules, and the list line shape |
| `spec/STATUS.md`                 | The rows of this plan                              |

## Work packages

1. **Create and list.** The verb module with `create` and `list`, the risk walk
   that list reports, the two rows, and the group form. Acceptance: the create
   and the list cases of `t/fugubench/worktree-verb.t` pass, and the SIGTERM
   case leaves no worktree and no branch.
2. **Remove.** The `remove` subcommand over the risk walk, the branch deletion,
   and the parent prune. Acceptance: the remove cases of
   `t/fugubench/worktree-verb.t` pass.
3. **Clone and the port.** The `clone` subcommand, and the ported test. The port
   lands here because each of its subtests calls `remove` or `clone`.
   Acceptance: `t/fugubench/worktree.t` passes, and its diff against the
   Workspace test holds the invocation, the fixture, and the dropped assertion
   only.

## Tests

Each test runs `bin/fugubench` as a child with `-Ilib`, against a temporary
repository with one commit on `main` and an empty `.toolingrc`. No test reads
the operator home, and no test writes outside its temporary tree.

`t/fugubench/worktree.t` is the port. It covers the clone of a `.env` file, the
listing, and the refusal of an uncommitted change. It covers the refusal of a
commit that no remote holds, `--force`, a merged branch with no remote, and a
dirty nested clone.

`t/fugubench/worktree-verb.t` covers:

- `create` prints the path as the only line of standard output. The branch and
  the worktree exist, and a bootstrap target sees `MAIN=<root>`.
- `create` refuses a name that starts with `-` or `.`, and a name with `..`. It
  refuses an existing directory, an existing branch, and a name inside an
  existing worktree. Each refusal leaves no branch and no directory.
- A failed bootstrap and a SIGTERM during a bootstrap each leave no worktree, no
  branch, and no empty parent. After the signal, the child of the bootstrap is
  gone.
- `remove` removes a locked worktree, a directory that git does not know, and a
  worktree that a user deleted by hand. A second run exits 0.
- `remove` never deletes `main` or the checked-out branch, and it refuses a
  symbolic link that resolves outside the base.
- `list` prints `no worktrees` without a worktree, and the `?` age for an
  unreadable `.git` file.
- `clone` makes a local clone with the origin URL of the source, and it clones
  each child of a directory. It copies a `.env` at depth with its mode, and it
  skips a `.env` symbolic link.
- `clone` keeps an existing destination, and it replaces a destination symbolic
  link. It refuses a `..` path, skips an absent path with a message, and changes
  nothing in the main checkout.
- A `-C` that names a linked worktree exits 1.

## Acceptance

- `make check` passes, with the two tests in the `t/fugubench/` tier.
- `spec/STATUS.md` sets WT-CREATE, WT-REMOVE, WT-LIST, WT-CLONE, and WT-SAFETY
  to `done`. It keeps CLI-VERBS and CLI-SANDBOX at `partial`, and each note
  drops `worktree` from the absent verbs. It sets CLI-CONFORMANCE to `partial`,
  and the note names the tests of `wiki.pl` and `traces.pl`, and
  CLI-CONFORMANCE-2.
- The change deletes this plan.

## Open questions

None. The script holds every design choice, and the specification records it.
