# 004 — The hook verb and the doctor

## Status

In progress, and it waits on no other plan. Work package 1 landed: the four
events of the `hook` verb, with the payload read, the early exits, and the
checkout of the payload. Work packages 2 and 3 stay open, and each one can land
now. The Workspace follows with a change of its own: its hook entries and its
`jq` dependency.

Implements: HOOK-INSTALL. Implements: CLI-DOCTOR.

Implements: CLI-VERBS. This plan adds the `doctor` verb to the table.

Implements: CLI-SANDBOX. This plan adds the row of that verb.

## Purpose

The hook verb holds the Claude Code assumptions (D-10) and reads each payload
itself (D-07), so no host needs `jq`. The doctor reports the state of one
checkout in a shape that a make target can gate on. It repairs the debris of the
old open race: a stopped rebase over a header-only session page.

## Scope

In scope:

- The `install` subcommand of the `hook` verb, in `App::FuguBench::Hook`.
- The `doctor` verb, `App::FuguBench::Doctor`, with `--fix`.
- The sandbox row and the verb table entry of `doctor`.
- The tests of the two work packages.

Out of scope:

- The wiki verb and the worktree verb. `spec/wiki.md` and `spec/worktree.md`
  hold their design.
- The Workspace settings file. The Workspace lands that change.

## Constraints that shape the design

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
`git show REBASE_HEAD:<page>`. The row of `doctor` pledges
`stdio rpath proc exec` for that call and for `--fix`. Git runs as a child, so
the row unveils nothing, as plan 001 states for a verb with a child.

**The fix has one shape.** `doctor --fix` runs `git rebase --skip` in the clone
when the pending commit has the shape of the race. That commit adds one file,
the file is a session page, and the text after `## Observations` is blank. Every
other pending commit is a refusal, with the reason on standard error.

## The interface contract

### App::FuguBench

The verb table gains `doctor`, and the sandbox table gains its row. That row
unveils nothing.

### App::FuguBench::Hook

`install` writes `<root>/.claude/settings.json` of the checkout of the
dispatcher: the four entries of `entries` under `hooks`, and `head` at
`worktree.baseRef`. It returns 0, and 1 when the file does not parse or the
write fails. The usage line of the verb gains the word.

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

| File                           | Change                                   |
| ------------------------------ | ---------------------------------------- |
| `lib/App/FuguBench.pm`         | The table entry and the row of `doctor`  |
| `lib/App/FuguBench/Hook.pm`    | `install` and `entries`                  |
| `lib/App/FuguBench/Hook.pod`   | The contract of `install`                |
| `lib/App/FuguBench/Doctor.pm`  | New: the report and `--fix`              |
| `lib/App/FuguBench/Doctor.pod` | New: the contract                        |
| `t/fugubench/hook-install.t`   | New: the settings writer                 |
| `t/fugubench/doctor.t`         | New: the report, the rebase, and the fix |
| `spec/STATUS.md`               | The rows of this plan                    |

## Work packages

2. **The installer.** `install` and `entries`. Acceptance: `hook-install.t`
   passes, and `bunx prettier --check` accepts the written fixture.
3. **The doctor.** `Doctor.pm` and `--fix`. Acceptance: `doctor.t` passes, and
   `fugubench doctor` on this checkout prints `ok` lines only.

## Tests

Each test runs `bin/fugubench` as a child with `-Ilib`, and it writes inside its
temporary tree only. A wiki fixture is a bare origin and a checkout whose
`.toolingrc` names it as `wiki.origin` with a `file://` URL.

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

- `make check` passes, with the two tests in the tier.
- `spec/STATUS.md` sets HOOK-INSTALL and CLI-DOCTOR to `done`. It updates the
  `partial` notes of CLI-VERBS and CLI-SANDBOX.
- The change deletes this plan.

## Open questions

None. The entry of `hook install` carries no `statusMessage`, because the
specification names three keys and the harness names the event itself.
