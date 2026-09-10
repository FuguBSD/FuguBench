# 004 — The hook verb and the doctor

## Status

Proposed. It waits on plan 002 (the worktree verb) and plan 003 (the wiki verb):
`SessionStart` runs `wiki init` and `wiki open`, and `WorktreeCreate` runs
`worktree create`. It lands after both, in three work packages. The Workspace
follows with a change of its own. It replaces the four jq-based hook commands of
its `.claude/settings.json` with the output of `hook install`. It drops `jq`
from its manifests.

Implements: HOOK-EVENTS. Implements: HOOK-SESSION. Implements: HOOK-WORKTREE.
Implements: HOOK-INSTALL. Implements: CLI-DOCTOR.

Implements: CLI-VERBS. This plan adds the `hook` verb and the `doctor` verb to
the table.

Implements: CLI-SANDBOX. This plan adds the rows of the two verbs.

## Purpose

The hook verb holds the Claude Code assumptions (D-10) and reads each payload
itself (D-07), so no host needs `jq`. The doctor reports the state of one
checkout in a shape that a make target can gate on. It repairs the debris of the
old open race: a stopped rebase over a header-only session page.

## Scope

In scope:

- The `hook` verb, `App::FuguBench::Hook`, with the subcommands `SessionStart`,
  `SessionEnd`, `WorktreeCreate`, `WorktreeRemove`, and `install`.
- The `doctor` verb, `App::FuguBench::Doctor`, with `--fix`.
- The two sandbox rows, the two verb table entries, and the one-argument form of
  `checkout` in `App::FuguBench`.
- The tests of the three work packages.

Out of scope:

- The wiki verb and the worktree verb. Their plans hold their design.
- The Workspace settings file. The Workspace lands that change.

## Constraints that shape the design

**The payload comes first, and the checkout after.** The dispatcher of 001
builds the checkout from `-C` or from the current directory. The hook verb reads
the payload, builds `App::FuguBench::Checkout->new(start => $cwd)` from the
payload `cwd` (HOOK-EVENTS-5), and sets it on the dispatcher. This plan adds the
one-argument form `checkout($checkout)` to `App::FuguBench`. The sandbox row
enters before the verb runs, with the root of the current directory. The harness
runs a hook inside the checkout that it works in, so that root covers the
payload `cwd`.

**The hook verb calls the other verbs in-process.** It calls the `run` entry of
`App::FuguBench::Wiki->command` and of `App::FuguBench::Worktree->command` with
the dispatcher and the arguments, as the dispatcher does. No child perl runs,
and no option parses twice. A session event maps every non-zero return to a
warning and exit 0 (HOOK-EVENTS-3). `WorktreeCreate` returns the code of
`worktree create`, and its path line reaches standard output (WT-CREATE-5).
`SessionStart` lets the page line of `wiki open` reach standard output, and the
harness adds that line to the context of the session.

**The remove hint splits the path.** `WorktreeRemove` splits `worktree_path` at
the last `/<worktree.base>/` segment: the prefix is the root, and the suffix is
the name. The split prints a hint, and it finds no checkout, so CLI-CHECKOUT-4
holds. Without the segment, the verb prints the path alone. The implementation
adds the split sentence to HOOK-WORKTREE-2 with the code.

**One JSON writer, through JSON::PP.** `hook install` decodes the file with
JSON::PP, which is core (D-07). It encodes with `canonical`, an indent of two
spaces, no space before a colon, and a final newline, and it writes through
`Fugu::File->write_atomic`. Sorted keys make the second run byte-equal. The
writer keeps every key that it does not own, at the top level and under `hooks`.
An entry holds `type`, `command`, and `timeout`, and nothing else. A file that
does not parse is a failure, and the verb writes nothing. JSON::PP expands every
array, and prettier joins a short array of scalars on one line. The two agree on
a file whose arrays break, and the Workspace file is such a file.

**The doctor runs git for the report.** The pending commit of a stopped rebase
is `REBASE_HEAD`. The doctor lists its files with
`git show --name-status --format= REBASE_HEAD`, and it reads the page with
`git show REBASE_HEAD:<page>`. The row of `doctor` takes `stdio rpath proc exec`
for that call and for `--fix`. It takes the unveil list of the `wiki` row, so
the tool check on `PATH` and the git call see one view.

**The fix has one shape.** `doctor --fix` runs `git rebase --skip` in the clone
when the pending commit has the shape of the race. That commit adds one file,
the file is a session page, and the text after `## Observations` is blank. Every
other pending commit is a refusal, with the reason on standard error.

## The interface contract

### App::FuguBench

`checkout($checkout)` sets the checkout of the run and returns it. The verb
table gains `hook` and `doctor`. The sandbox table gains the row of `hook`, the
union of the `wiki` row and the `worktree` row, and the row of `doctor`.

### App::FuguBench::Hook

`command` returns the entry with the usage
`hook <SessionStart|SessionEnd|WorktreeCreate|WorktreeRemove|install>`. Another
first word is a usage error.

An event reads standard input to the end and decodes it. A payload that does not
parse warns and returns 0. A payload with `agent_id` returns 0 at once, and
reads no checkout. A payload without `cwd`, or a `cwd` with no `.toolingrc`
above it, warns. A session event then returns 0, and `WorktreeCreate` returns

1. Every event sets the checkout of the payload on the dispatcher.

`SessionStart` takes `session_id`, replaces each character outside letters,
digits, a dot, a dash, and an underscore with a dash, and runs `wiki init` and
`wiki open <project> <session>`. The project is the child of `wiki.projects`
under its home that holds the absolute `cwd`, and otherwise `wiki.project`. It
returns 0.

`SessionEnd` runs `wiki close <session>` and returns 0.

`WorktreeCreate` runs `worktree create <name>` and returns its code. A payload
without `name` returns 1.

`WorktreeRemove` writes `worktree kept: <path>` and
`to remove it: make -C <root> worktree-remove NAME=<name>` to standard error,
and returns 0. A payload without `worktree_path` warns and returns 0.

`install` writes `<root>/.claude/settings.json` of the checkout of the
dispatcher: the four entries of `entries` under `hooks`, and `head` at
`worktree.baseRef`. It returns 0, and 1 when the file does not parse or the
write fails.

`entries` returns a hash of the four events. Each value is one list with one
matcher-less group, and the group holds one entry. The entry holds `type` of
`command`, the command `"$CLAUDE_PROJECT_DIR/scripts/fugubench" hook <event>`,
and the timeout of HOOK-INSTALL-3. The doctor compares against this hash.

### App::FuguBench::Doctor

`command` returns the entry with the usage `doctor [--fix]`. The verb prints one
line for each check to standard output, `ok <check>: <detail>` or
`problem <check>: <detail>`, and returns 1 when any line starts with `problem`.

| Check                  | `ok` detail                            | `problem` detail                                                      |
| ---------------------- | -------------------------------------- | --------------------------------------------------------------------- |
| `version`              | The line of the `version` verb         | never                                                                 |
| `git`, `make`          | The path on `PATH`                     | `absent from PATH`                                                    |
| `downloader`           | The first of `curl`, `wget`, and `ftp` | `no curl, wget, or ftp on PATH`                                       |
| `hooks`                | `none`, when no event of the four      | never                                                                 |
| `hook <Event>`         | `installed`, equal to `entries`        | `absent`, or `differs from hook install`                              |
| `library`              | `absent`, or the clone path            | `stopped rebase, the pending commit adds <page>`, or `changes <list>` |
| `library` with `--fix` | `skipped the pending commit <page>`    | `stopped rebase, fix refused: <reason>`                               |

The library check reads `<home>/<wiki.dir>` of the checkout, and
`git rev-parse --verify --quiet REBASE_HEAD` in the clone tells a stopped
rebase.

## Files

| File                           | Change                                              |
| ------------------------------ | --------------------------------------------------- |
| `lib/App/FuguBench.pm`         | The two table entries, the two rows, `checkout($c)` |
| `lib/App/FuguBench.pod`        | The one-argument form of `checkout`                 |
| `lib/App/FuguBench/Hook.pm`    | New: the four events, `install`, and `entries`      |
| `lib/App/FuguBench/Hook.pod`   | New: the contract                                   |
| `lib/App/FuguBench/Doctor.pm`  | New: the report and `--fix`                         |
| `lib/App/FuguBench/Doctor.pod` | New: the contract                                   |
| `t/fugubench/hook.t`           | New: the four events on fixture payloads            |
| `t/fugubench/hook-install.t`   | New: the settings writer                            |
| `t/fugubench/doctor.t`         | New: the report, the stopped rebase, and the fix    |
| `spec/hooks.md`                | The split sentence of HOOK-WORKTREE-2               |
| `spec/STATUS.md`               | The rows of this plan                               |

## Work packages

1. **The four events.** `Hook.pm` with the payload read, the early exits, the
   checkout of the payload, and the four events. Acceptance: `hook.t` passes,
   and a payload of `t/ci/wiki.t` of the Workspace gives the same page.
2. **The installer.** `install` and `entries`. Acceptance: `hook-install.t`
   passes, and `bunx prettier --check` accepts the written fixture.
3. **The doctor.** `Doctor.pm` and `--fix`. Acceptance: `doctor.t` passes, and
   `fugubench doctor` on this checkout prints `ok` lines only.

## Tests

Each test runs `bin/fugubench` as a child with `-Ilib`, feeds a payload on
standard input, and writes inside its temporary tree only. A wiki fixture is a
bare origin and a checkout whose `.toolingrc` names it as `wiki.origin` with a
`file://` URL.

`t/fugubench/hook.t` covers:

- A payload with `agent_id` exits 0 and opens no page.
- `SessionStart` opens one page for the workspace, and one for a `cwd` under
  `Projects/<name>`, with the name from the path.
- A second `SessionStart` with one `session_id` prints the same page, and
  `SessionEnd` closes it. A `SessionEnd` with `{}` exits 0.
- A payload that does not parse exits 0 with a warning.
- `WorktreeCreate` prints the path as the only line, and the worktree exists. A
  payload without `name` exits 1.
- `WorktreeRemove` keeps the directory, prints the manual command with the root
  and the name, and exits 0.
- A word outside the five exits 2.

`t/fugubench/hook-install.t` covers:

- An absent file gets the four entries and `worktree.baseRef`.
- A file with other keys before and after keeps each of them, in sorted order.
- The second run leaves the bytes equal, and the file has two-space indents, no
  space before a colon, and a final newline.
- A file that does not parse exits 1 and stays as it was.

`t/fugubench/doctor.t` covers:

- A `PATH` of one directory with a link to `git` alone gives `problem make` and
  `problem downloader`, and exit 1.
- No settings file gives `ok hooks: none`. A file after `hook install` gives
  four `ok hook` lines, and a changed timeout gives one `problem` line.
- A clone in a stopped rebase over a header-only session page gives the
  `problem library` line with the page. `--fix` skips it, and the next run gives
  `ok library`.
- A pending commit with an observation line refuses `--fix`, and the rebase
  stays.

## Acceptance

- `make check` passes, with the three tests in the tier.
- `spec/STATUS.md` sets HOOK-EVENTS, HOOK-SESSION, HOOK-WORKTREE, HOOK-INSTALL,
  and CLI-DOCTOR to `done`. It updates the `partial` notes of CLI-VERBS and
  CLI-SANDBOX.
- `spec/hooks.md` holds the split sentence of HOOK-WORKTREE-2.
- The change deletes this plan.

## Open questions

None. The entry of `hook install` carries no `statusMessage`, because the
specification names three keys and the harness names the event itself.
