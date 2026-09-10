# 005 — The traces verb

## Status

Proposed. It lands after plan 001, and it waits on nothing else. After it lands,
the Workspace swaps its `make traces` target to the verb, in a change of the
Workspace.

Implements: TRACE-NAME. Implements: TRACE-COLUMNS. Implements: TRACE-USAGE.
Implements: TRACE-PANEL. Implements: TRACE-SUB.

Implements: CLI-VERBS. This plan adds the `traces` verb to the table of the
dispatcher. The unit stays `partial` until the last verb lands.

Implements: CLI-SANDBOX. This plan adds the row of `traces`, with the trace root
as a read-only path. The unit stays `partial` until the last verb lands.

Implements: CLI-CONFORMANCE without CLI-CONFORMANCE-2. This plan ports the
Workspace test `t/ci/traces.t`, with the invocation and the fixture changed, as
the CLI-CONFORMANCE-1 text of plan 002 allows. The tests of `worktree.pl` and
`wiki.pl` come with their verbs, and the dry-run trace of `deps` comes with the
installer. The unit stays `partial` until those plans land.

## Purpose

The Workspace measures its Claude Code sessions with `scripts/traces.pl`, and
Workspace WS-SESSION holds the yardstick. The script derives the checkout name
from the location of its own file, so it measures one repository only. This plan
moves the yardstick into `fugubench traces`, so every checkout of the
organization gets the same measure from the one program. The verb derives the
name from the checkout root, and it keeps every column, every count, and every
test of the script.

## Scope

In scope:

- The `traces` verb, `App::FuguBench::Traces`, with `--root <dir>` and
  `--name <name>`.
- The `traces` entry of the command table, and its sandbox row.
- The port of the Workspace test `t/ci/traces.t` to `t/fugubench/traces.t`.

Out of scope:

- The `make traces` target of the Workspace. The Workspace swaps it to the verb
  in a change of its own.
- A new column or a new count. The verb measures what the script measures.
- The hook verb. It shares the Claude Code assumptions of D-10 with `traces`,
  and nothing else.

## Constraints that shape the design

**The name comes from the checkout root, not from the file.** The script cuts
the path of its own file at the last `.claude/worktrees/` marker. The program
runs from a pack in `~/.local/bin`, so its location names no checkout. The verb
takes the root of CLI-CHECKOUT instead: the `-C` directory, or the walk to the
nearest `.toolingrc`. It resolves the root to its real path, and it cuts the
path at the last marker, as TRACE-NAME-1 says. A worktree holds its own
`.toolingrc`, so the walk stops in the worktree, and the cut reaches the
checkout. CLI-CHECKOUT-4 names this cut as the one exception. The cut lives in
the verb module, so the checkout module holds no Claude Code assumption (D-10).

**The edit boundary is the cut path.** TRACE-PANEL-3 names "the checkout" as the
boundary of an absolute target. The script takes the cut path, so a write in a
worktree counts as an edit of the checkout. The verb keeps that: the boundary is
the path of TRACE-NAME-1, and `--name` does not change it. The implementation
adds the words "of TRACE-NAME-1" to TRACE-PANEL-3 with the code.

**The sandbox row needs the trace root.** `traces` runs no child command, so its
row names no command, and it needs no network promise (CLI-SANDBOX-2). It reads
the trace root, `~/.claude/projects/` or the `--root` value, and the row adds
that path `r`. TRACE-NAME-3 names the path, so it falls in the classes of
CLI-SANDBOX-2, and this plan changes no rule of cli.md. The row depends on a
parsed option, so the dispatcher resolves the row after the parse and before the
entry.

**The record filter is the contract.** A full parse of every record costs
minutes over a long history (TRACE-USAGE-2). The verb decodes each record until
one carries a timestamp, and it takes that time as the start. After that, it
decodes a line only when the line holds the word `assistant`, and it keeps a
record of type `assistant` only. Every usage block and every `tool_use` block
sits in an assistant record, so the filter loses no count. A line that fails to
decode is no record.

**JSON through JSON::PP.** The program runs on core modules alone
(CLI-PROGRAM-1), and JSON::PP is one. Fugu holds no JSON module, so no CLI-FUGU
rule changes.

**The test comes over with its invocation and its fixture changed.**
CLI-CONFORMANCE-1, as plan 002 rewords it, holds the test to the assertions of
the script. Two places of the test name the script: the `_traces` helper, and
the last test, which copies the script into a nested marker path. The helper
runs `bin/fugubench -C <checkout> traces` instead. The last test replaces the
copy with a `-C` directory that holds the marker twice and its own `.toolingrc`.
The boundary sessions build their paths from the `-C` directory, so no assertion
holds an operator path.

## The interface contract

### The traces verb

`App::FuguBench::Traces->command` returns the entry of the Fugu LIB-CLI table.
The options are `--root <dir>` and `--name <name>`. The verb takes no argument,
and an argument is a usage error, exit 2.

`run` derives the name from the checkout root when `--name` is absent. It takes
`~/.claude/projects` as the trace root when `--root` is absent. A trace root
that is no directory is a failure, exit 1, with the path in the message.

The verb prints the header, then one row for each session with a request. The
rows sort by start time, in the column format of the script. When no directory
matches the name, it prints `no session of <name>` and exits 0.

### The sandbox row

The row of `traces` holds the read promises, no network promise, and no command.
Its unveil list holds the shared paths of plan 001 and the trace root `r`.

## Files

| File                           | Change                                         |
| ------------------------------ | ---------------------------------------------- |
| `lib/App/FuguBench/Traces.pm`  | New: the verb                                  |
| `lib/App/FuguBench/Traces.pod` | New: the contract                              |
| `lib/App/FuguBench.pm`         | The `traces` entry and its sandbox row         |
| `t/fugubench/traces.t`         | New: the port of the Workspace `t/ci/traces.t` |
| `spec/traces.md`               | The boundary words of TRACE-PANEL-3            |
| `spec/STATUS.md`               | The rows of this plan                          |

## Work packages

An implementer takes the packages in order. Each one ends in a passing
`make check`.

1. **The name and the match.** The module with `command`, the options, the name
   derivation, the directory match, and the `no session of` line. The tally
   counts the requests only, so a session gets its row and no other count. The
   `traces` entry of the command table, and its sandbox row. The test file with
   the fixture. Its assertions cover the match: the worktree, the project clone,
   the sibling, the absent name, and the two markers. Acceptance: the test
   passes, and `fugubench traces --root <dir>` lists a fixture session.

2. **The columns and the counts.** The tally of one trace file: the start time,
   the peak, the output, the panel, and the edits. The sub-agent totals, and
   `rev-peak` through the meta files. The rest of the assertions of the
   Workspace test. Acceptance: the test holds every assertion of the Workspace
   test, and it passes.

## Tests

`t/fugubench/traces.t` is the Workspace test `t/ci/traces.t` with the invocation
and the fixture changed, as the CLI-CONFORMANCE-1 text of plan 002 allows. It
runs `bin/fugubench` as a child with `-Ilib`. It builds its fixture in one
temporary tree: a checkout directory with an empty `.toolingrc`, and a trace
root beside it. No test reads the operator home, and no test writes outside the
tree.

The fixture root holds the checkout, one worktree of it, one project clone in
it, and one sibling checkout. The checkout holds the sessions of the Workspace
test. The assertions cover:

- The exit code, the start time, the request count, the peak, and the output of
  the main session.
- The panel count with a fixer, the edits after the first launch, the sub-agent
  totals, and `rev-peak` through the meta files.
- The worktree and the project clone join, and the sibling stays out.
- A session with no request gets no row, and a name with no directory gets the
  `no session of` line.
- The scratch paths, the near misses, the checkout boundary, the operator home,
  and the sibling checkout, in the edits column.
- The catch-all agent type falls back to the description.
- With no `--name`, a `-C` directory under two markers names the inner checkout,
  and the outer checkout stays out.

## Acceptance

- `make check` passes, and `t/fugubench/traces.t` runs in `make test`.
- The test passes on the perl of the host, with the installed Fugu.
- `spec/STATUS.md` sets TRACE-NAME, TRACE-COLUMNS, TRACE-USAGE, TRACE-PANEL, and
  TRACE-SUB to `done`. It keeps CLI-VERBS and CLI-SANDBOX at `partial`, with
  `traces` gone from each note. It sets CLI-CONFORMANCE to `partial`, and the
  note names the tests of `worktree.pl` and `wiki.pl`, and the dry-run trace of
  CLI-CONFORMANCE-2.
- The change deletes this plan.

## Open questions

None. The design comes from Workspace WS-SESSION, and the one change against the
script is the name derivation of TRACE-NAME-1.
