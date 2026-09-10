# 001 — The program: dispatch, checkout, configuration, and version

## Status

Proposed. It can land now. It depends on no other plan of this repository, and
every other plan builds on it.

Implements: CLI-PROGRAM. Implements: CLI-CHECKOUT. Implements: CLI-CONFIG.
Implements: DIST-VERSION.

Implements: CLI-VERBS. This plan lands the dispatcher, the verb table, and the
`version` verb. Each later plan adds its verb, and the unit stays `partial`
until the last one lands.

Implements: CLI-FUGU. This plan uses the dispatch, the process, the file, the
log, and the sandbox modules. The verifier and the downloader come with the
dependency installer, so the unit stays `partial` until then.

Implements: CLI-SANDBOX. This plan lands the mechanism and the promise table.
Each later plan adds the row of its verb.

Defers: CLI-DOCTOR. Defers: CLI-CONFORMANCE. The doctor lands with the hooks,
and the conformance tests land with the verbs that they cover.

## Purpose

Every verb of `fugubench` shares one dispatcher, one checkout discovery, one
configuration reader, one sandbox entry, and one channel discipline. This plan
lands that shared part with one small verb, `version`, so each later plan adds
one verb and nothing else. The tests of this plan hold the shared contract, and
each later verb inherits them.

## Scope

In scope:

- The executable `bin/fugubench` and the dispatcher `App::FuguBench`.
- The checkout discovery and the configuration reader,
  `App::FuguBench::Checkout`.
- The sandbox entry and the promise table, in `App::FuguBench`.
- The `version` verb.
- The test tier `t/fugubench/`, and the convention test that holds every file to
  the floor and to the Fugu module set.

Out of scope:

- Every other verb. Each one lands in its own plan.
- The pack. The program runs from the checkout with an installed Fugu until the
  pack plan lands.

## Constraints that shape the design

**The floor is v5.34, and the snapshot is not there yet.** Every file of this
repository starts with the four-line pragma block that `lib/CLAUDE.md` names.
The installed Fugu 0.4.0 holds `use v5.36`, so the program runs on perl 5.36 or
later until Fugu plan 008 lands in a release. The convention test holds the
files of this repository to the block, and nothing else.

**One dispatcher.** Fugu LIB-CLI parses the global options, finds the verb,
parses the options of the verb, and calls it. The exit codes of Fugu LIB-CLI are
the codes of the program: 0, 1, 2, and 3. The dispatcher must never return the
timeout code of the library, and no verb defines another.

**Two channels.** Standard output carries the result line of a verb, and nothing
else. The logger of Fugu LIB-LOG writes to standard error. A child command runs
through `Fugu::Process->run`, and the verb writes the captured output of the
child to standard error, in full. With `--verbose`, the dispatcher writes each
command line to standard error before it runs.

**A verb declares its subcommands as one word.** Fugu LIB-CLI takes one level of
commands. A verb with subcommands, such as `worktree create`, reads the
subcommand as its first argument and dispatches on it. The dispatcher holds the
verb, and the verb module holds its subcommands.

**The checkout walk has two stops.** The first stop is the nearest directory
with `.toolingrc`, and that directory is the root. A key with no default stops
the verb with a configuration error when no `.toolingrc` on the walk holds it. A
key with a default takes the default when no file on the walk holds it. The
directory of the file that holds a key is the home of that key. A verb names the
anchor of each relative value. The wiki verb anchors at the home of
`wiki.origin`, and the worktree verb anchors at the root. A clone under
`Projects/` holds no `wiki.` key, so the home of `wiki.origin` is the workspace.
The implementation adds the home sentence to CLI-CONFIG-2 with the code.

**The walk runs on demand.** The dispatcher builds the checkout on the first
call of `checkout`, and a verb that reads no checkout needs no `.toolingrc`. The
verbs `version`, `shim`, `install`, and `update` read none, so `curl | sh` works
in a home without one. The implementation adds those verbs to the exception of
CLI-CHECKOUT-5 with the code.

**A shape check guards every value.** A directory value is a relative path with
no `..` segment. A URL holds a scheme. A name that reaches a command passes the
check of its verb first. The checkout module holds the two shared checks, and a
verb module holds its own.

**The sandbox is a table.** One table in `App::FuguBench` maps each verb to its
pledge promises and to its unveil paths. The dispatcher calls Fugu LIB-SANDBOX
with the row of the verb before the verb runs. On another platform the call
changes nothing. This plan fills the row of `version`, and each verb plan adds
its row. The unveil list holds the checkout root, `~/.local/bin`,
`~/.cache/fugubench`, and one temporary directory. It adds the paths of
`Fugu::Sandbox->perl_lib_dirs` and `Fugu::Sandbox->system_paths`.

**The version comes from the stamp.** Fugu REL-VERSION-2 stamps `our $VERSION`
into every staged package at the dist build. In a checkout no stamp exists, and
the version is `0.0.0`. The Fugu version is `Fugu->VERSION` of the loaded
library: the installed one in a checkout, and the snapshot in the pack.

## The interface contract

### bin/fugubench

The executable loads `App::FuguBench` and exits with the return value of
`App::FuguBench->new->run(@ARGV)`.

### App::FuguBench

`new` builds the dispatcher over Fugu LIB-CLI. The global options are `-C <dir>`
and `--verbose`. The command table holds one entry for each verb module that
this repository has.

`run(@argv)` parses, enters the sandbox row of the verb, and dispatches. It
returns the exit code. The row resolves after the parse, so a row can name a
path that an option gives, such as the trace root of `traces`.

`checkout` returns the `App::FuguBench::Checkout` of the run, and builds it on
the first call. The start is the `-C` value, or the current directory. A walk
that finds no `.toolingrc` ends the verb with exit 3 and the start directory in
the message. `checkout($checkout)` sets one, for a verb that reads its start
from a payload.

`command(\@cmd, %args)` runs one child through `Fugu::Process->run`, with no
shell. It writes the trace line under `--verbose`, and it writes the captured
standard error of the child to standard error. It returns the captured standard
output, or undef with the reason in `error`. With `group => 1`, the child starts
in its own session through `spawn_command`, and `child` holds its pid while it
runs. A signal handler then stops the group through `Fugu::Process->terminate`
before its cleanup.

Each verb module has one class method, `command($verb)`, that returns the entry
of the Fugu LIB-CLI table: `summary`, `usage`, `options`, and `run`. A module
that holds one verb ignores the name. The body receives the dispatcher and the
arguments.

### App::FuguBench::Checkout

`new(start => $dir)` walks up from the start to the nearest `.toolingrc`. It
returns undef when the walk reaches the filesystem root.

`root` returns the directory of the first `.toolingrc`.

`config($key)` returns the value of the key, and its home, from the nearest
`.toolingrc` on the walk that holds the key. A key of the table in
[cli.md](../../spec/cli.md#cli-config) with a default returns the default and
the root when no file holds it. Another key returns undef.

`dir_value($value)` and `url_value($value)` are the two shape checks. Each one
returns the value, or undef with the reason in `error`.

### The version verb

`App::FuguBench::Version->command` prints `fugubench <version> (Fugu <version>)`
to standard output and returns 0.

## Files

| File                             | Change                                                             |
| -------------------------------- | ------------------------------------------------------------------ |
| `bin/fugubench`                  | New: the executable                                                |
| `lib/App/FuguBench.pm`           | New: the dispatcher and the sandbox table                          |
| `lib/App/FuguBench.pod`          | New: the contract                                                  |
| `lib/App/FuguBench/Checkout.pm`  | New: the walk and the configuration reader                         |
| `lib/App/FuguBench/Checkout.pod` | New: the contract                                                  |
| `lib/App/FuguBench/Version.pm`   | New: the version verb                                              |
| `lib/App/FuguBench/Version.pod`  | New: the contract                                                  |
| `t/fugubench/cli.t`              | New: the channels, the codes, and the help                         |
| `t/fugubench/checkout.t`         | New: the walk, the keys, and the shape checks                      |
| `t/fugubench/conventions.t`      | New: the pragma block and the Fugu module set                      |
| `mk/local.mk`                    | `TEST_GLOBS` gains `t/fugubench/*.t`                               |
| `spec/cli.md`                    | The home sentence of CLI-CONFIG-2, and the verbs of CLI-CHECKOUT-5 |
| `spec/STATUS.md`                 | The rows of this plan, and `lib` in the code roots of `dist.md`    |

## Tests

Each test runs `bin/fugubench` as a child with `-Ilib`, so the test sees the
process as a hook does. No test reads the operator home, and no test writes
outside its temporary tree.

`t/fugubench/cli.t` covers:

- `--help` and `version --help` print to standard output and exit 0.
- An unknown verb, a bad option, and no verb each print the usage to standard
  error and exit 2.
- `version` prints one line of the shape `fugubench 0.0.0 (Fugu <version>)`, and
  nothing on standard error.
- `version` in a directory with no `.toolingrc` above it exits 0, because the
  verb reads no checkout.

`t/fugubench/checkout.t` covers:

- The walk finds `.toolingrc` in the start, in a parent, and in the root of a
  nested clone. It returns undef at the filesystem root, and the first verb that
  reads a checkout proves the exit 3 through the dispatcher.
- A key in the nearest file wins over the same key in a parent file.
- A key absent in the nearest file comes from the parent file, with the home of
  the parent.
- Each default of the table, and the configuration error of `wiki.origin`.
- A `..` segment, an absolute path, and a URL without a scheme each fail the
  shape check.
- A comment line and an unknown key change nothing.

`t/fugubench/conventions.t` covers:

- Every `.pm`, every `.t`, and `bin/fugubench` hold the four pragma lines in
  order, before the first `package` line.
- Every `use Fugu::` line of `lib/` names a module of the set that CLI-FUGU-1
  names.
- No file of `lib/` holds a `package Fugu::` line, and no `use App::` line names
  a module outside `App::FuguBench`.

## Acceptance

- `make check` passes, with the new tier in `make test`.
- The three tests pass on the perl of the host, with the installed Fugu.
- `spec/STATUS.md` sets CLI-PROGRAM, CLI-CHECKOUT, CLI-CONFIG, and DIST-VERSION
  to `done`. It sets CLI-VERBS, CLI-FUGU, and CLI-SANDBOX to `partial`, and each
  note names the absent part.
- The change deletes this plan.

## Open questions

None. The operator chose Perl on Fugu on 2026-09-10, and the module layout
follows the verb table.
