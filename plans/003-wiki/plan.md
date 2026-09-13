# 003 — The wiki verb

## Status

Packages 1 and 2 landed: the module, `init`, `open`, `note`, `admit`, and
`close`. Package 3 waits on nothing. Plan 004 builds on this plan:
`hook SessionStart` and `hook SessionEnd` call the `init`, `open`, and `close`
subcommands of this module. The hook subcommands `hook-start` and `hook-end` of
the Workspace script are not part of this plan. The hook subtest of
`t/ci/wiki.t` waits for plan 004 with them.

The Workspace follows with a change of its own: its `.toolingrc` key and its
callers of the script.

Implements: WIKI-STATUS.

Implements: CLI-VERBS. Implements: CLI-SANDBOX. This plan adds the `wiki` verb
and its sandbox row. Both units stay `partial` until the last verb lands.

Implements: CLI-CONFORMANCE without CLI-CONFORMANCE-2. This plan ports five
subtests of `t/ci/wiki.t` of the Workspace. The port changes the invocation and
the fixture, as the CLI-CONFORMANCE-1 text of plan 002 allows. The unit stays
`partial` until the worktree, the traces, and the deps plans land their parts.
Plan 002 landed that rewording of CLI-CONFORMANCE-1, and this plan points at the
landed text.

## Purpose

`fugubench wiki` replaces `scripts/wiki.pl` of the Workspace. The script counted
the pages of a stale clone. On 2026-09-09 two parallel sessions of one day took
one page name. The rebase of the loser stopped on an add/add conflict in its
worktree clone. This plan ports the script into the program, and it adds the
fetch before the count and the rename on a collision (D-08).

## Scope

In scope:

- `App::FuguBench::Wiki` with the subcommands `init`, `open`, `note`, `admit`,
  `close`, `status`, and `candidates`.
- The fetch before the count, and the rename on a rejected push.
- The push retry: fetch, rebase, and retry, three times at most, never a force.
- The sandbox row of `wiki`.
- The port of five subtests of `t/ci/wiki.t`, and the new tests of the two race
  rules.

Out of scope:

- The hook events, and the hook subtest of `t/ci/wiki.t`. Plan 004 lands them.
- The doctor report of a stopped rebase, CLI-DOCTOR-2.

## Constraints that shape the design

**The home of `wiki.origin` anchors the library.** A clone under `Projects/` is
a checkout of its own, and its root holds no library. `wiki.dir` has a default,
so its home is the root when the file omits it. `wiki.origin` has no default, so
its home is the directory of the file that holds it: the workspace. The library
directory is `<home of wiki.origin>/<wiki.dir>`. Plan 001 lands the anchor in
CLI-CONFIG-2, the `wiki.dir` row, and CLI-CHECKOUT-2, so this plan changes no
rule of cli.md.

**A missing `wiki.origin` stops `init` alone.** `init` needs the key to clone,
so an absent key stops it with a configuration error, and the message names the
key (CLI-CONFIG-2). Every other subcommand treats an absent key as an absent
clone: it reports the absence on standard error and exits zero (WIKI-CLONE-3).
The table of CLI-CONFIG names `init` as the verb that stops, and WIKI-STATUS-3
holds for `candidates`.

**The fetch comes first.** `open` fetches the current branch of the origin
before it picks `<n>`. When the local branch has no commit of its own, the verb
fast-forwards it, so a stale clone pushes once. The count takes the union of the
pages in the working tree and the pages of `origin/<branch>`, and `<n>` is the
first free number. A failed fetch warns, and the count is local: a checkout
without network access is normal.

**One retry loop, and the rename comes before the rebase.** Every push runs
through one loop of three tries. A rejected push fetches the branch. When the
fetched branch holds the page of the commit, `open` renames its page to the next
free `<n>` and amends the commit. Then the loop rebases onto `origin/<branch>`,
and it pushes again. A failed rebase aborts at once, so no stopped rebase stays
behind. After the third try the verb warns, and the commit stays local. No git
call carries `--force`.

**The conformance test pins the diagnostics.** `t/ci/wiki.t` merges the two
channels, and it asserts the words `already open`, `already closed`,
`rebasing and retrying`, `open sessions: none`, `claim(s)`, and
`unpushed commits`. The verb keeps those words, on the channel that
CLI-PROGRAM-4 gives them.

**Git runs in the clone.** Each git call goes through `$app->command` with `cwd`
set to the library directory. The captured output of git goes to standard error.
The verb writes files inside the clone only, and it checks each page name before
the path forms.

**The sandbox row is pledge-only.** Git pushes, so the row of `wiki` pledges
`stdio rpath wpath cpath fattr proc exec inet dns`. Plan 001 lists `wiki` among
the verbs with a network promise in CLI-SANDBOX-2. Git runs as a child, so the
row unveils nothing, as plan 001 states for a verb with a child. The `<file>` of
`note` and `admit` must sit under the root or the temporary directory. The note
skill writes it under `scratch/` of the root.

## The interface contract

### App::FuguBench::Wiki

`command` returns the entry of the Fugu LIB-CLI table. `run($app, $sub, @args)`
dispatches one subcommand, and it returns the exit code. The hook verb calls it
with `init`, `open`, and `close`, in process.

An unknown subcommand, a wrong argument count, or an invalid name is a usage
error. The message names the value, and the exit code is 2. In `init`, an absent
`wiki.origin` on the walk exits 3, and the message names the key. In every other
subcommand, an absent clone writes `no library at <dir>` to standard error, and
an absent key writes `no library, wiki.origin is unset`. The subcommand then
exits 0 with no result line.

| Subcommand   | Arguments             | Result line                                    | Exit code                                                    |
| ------------ | --------------------- | ---------------------------------------------- | ------------------------------------------------------------ |
| `init`       | none                  | The library directory, on a fresh clone only   | 0; a failed clone warns and exits 0; 3 without `wiki.origin` |
| `open`       | `<project> <session>` | The final page name, the only line             | 0                                                            |
| `note`       | `<page> <file>`       | The page name, with `.md`                      | 0; no page, no file, or an empty file: 1                     |
| `admit`      | `<page> <file>`       | The page name, with `.md`                      | 0; no page, no file, or an empty file: 1                     |
| `close`      | `<session>`           | The page name, when the page changes           | 0; no page, or a closed page: 0, no line                     |
| `status`     | none                  | The `open sessions:` report, then the unpushed | 0                                                            |
| `candidates` | none                  | One line per candidate, or the none line       | 0, also with no clone and with no page                       |

The commit subjects are `open: <page>`, `note: <page>`, `admit: <page>`, and
`close: <page>`. A failed push warns and exits 0 in every subcommand, and the
commit stays for the next push.

`status` prints `open sessions:` and one line for each open session, with the
page, the `Claim:` count, and the `Admitted:` count. With no open session it
prints `open sessions: none`. The last line is `unpushed commits: <n>`.

`candidates` prints `<age> d  <date>  <text>` for each undelivered candidate,
and `no undelivered candidate` when none exists. With no page it writes
`no Rule-candidates.md, nothing to report` to standard error.

## Files

| File                         | Change                                           |
| ---------------------------- | ------------------------------------------------ |
| `lib/App/FuguBench/Wiki.pm`  | The subcommands of packages 2 and 3              |
| `lib/App/FuguBench/Wiki.pod` | The contract of each subcommand that follows     |
| `t/fugubench/wiki.t`         | New: the port of `t/ci/wiki.t`                   |
| `t/fugubench/wiki-push.t`    | The capture subtests of the retry and the rebase |
| `spec/STATUS.md`             | The rows of this plan                            |

## Work packages

1. **init, pages, and open.** Landed. The module, the library directory, the
   page and token checks, and `init`. Then `open`: the fetch, the fast-forward,
   the union count, the save path, and the retry loop with the rename.
   Acceptance: `t/fugubench/wiki-init.t` passes, and the `open` subtests of
   `t/fugubench/wiki-push.t` pass.
2. **note, admit, and close.** Landed. The append after one blank line, the
   `Closed:` line, and the idempotence of `close`. Acceptance:
   `t/fugubench/wiki-push.t` passes in full.
3. **status and candidates.** The report of the open sessions, the unpushed
   count, and the candidate list with the joined continuation lines. Acceptance:
   `t/fugubench/wiki.t` passes in full.

## Tests

Each test runs `bin/fugubench` as a child with `-Ilib`. A test makes a temp tree
with a bare repository as the origin, and one or two checkouts that clone it. A
checkout holds a `.toolingrc` with `wiki.origin file://<bare repository>`, so
the URL holds a scheme. The child runs with `HOME` set to the temp tree and with
`GIT_CONFIG_NOSYSTEM=1`, so no test reads the operator home or the signing
agent. The bare origin sets `receive.denyNonFastForwards`, as the ruleset of the
library does.

`t/fugubench/wiki.t` is `t/ci/wiki.t` with the invocation and the fixture
changed, as the CLI-CONFORMANCE-1 text of plan 002 allows. The `scripts/wiki.pl`
marker of a checkout becomes its `.toolingrc`, and `_wiki` runs the program. It
covers the idempotent `open`, and the `note` that reaches the origin. It covers
the rejected push that rebases and retries, and the page names that stay inside
the clone. It covers the idempotent `close`, and the candidates with a wrapped
`Delivered:`.

`t/fugubench/wiki-init.t` covers:

- `init` clones into the library directory and prints the path. A second run
  prints nothing and changes nothing.
- A `wiki.origin` that no repository answers: `init` warns, exits 0, and makes
  no directory.
- No `wiki.origin` on the walk: `init` exits 3, and the message names the key.
  Every other subcommand reports the absent key on standard error, exits 0, and
  prints no result line.
- A checkout under `Projects/` of a workspace: the library is the `Wiki` of the
  workspace, not of the clone.
- No clone: every subcommand except `init` reports the absence on standard
  error, exits 0, and prints no result line.

`t/fugubench/wiki-push.t` covers:

- WIKI-OPEN-2: a peer clone opens first and pushes `-1`. The stale clone opens
  and prints `-2`, with no retry message, and the origin holds both pages.
- WIKI-OPEN-3: a `pre-push` hook of the first clone runs the `open` of the peer
  once. So the origin gains `-1` after the fetch and before the push. The first
  clone prints `-2`, and the origin holds both pages. The commit subject names
  `-2`, the working tree is clean, and no `rebase-merge` directory exists.
- WIKI-CAPTURE-5: two clones append to one page, so the rebase of the loser
  conflicts. The loser aborts the rebase, warns, exits 0, and keeps one unpushed
  commit on its branch.
- WIKI-CAPTURE-5: under `--verbose`, no traced git command holds `--force` or
  `-f`.
- WIKI-CAPTURE-6: with a detached HEAD, `note` commits, warns, exits 0, and the
  origin does not change.

## Acceptance

- `make check` passes.
- The three tests pass on the perl of the host, with the installed Fugu, and
  without network access.
- `spec/STATUS.md` sets WIKI-CLONE, WIKI-PAGES, WIKI-OPEN, WIKI-CAPTURE,
  WIKI-STATUS, and WIKI-CONFINE to `done`. CLI-VERBS and CLI-SANDBOX stay
  `partial`, and each note drops `wiki`. CLI-CONFORMANCE becomes `partial`, and
  its note names the worktree tests, the traces tests, the hook subtest, and the
  deps trace as absent.
- The change deletes this plan.

## Open questions

None. The row of `wiki` unveils nothing, so a push over HTTPS reads the
credential helper and the CA bundle of git.
