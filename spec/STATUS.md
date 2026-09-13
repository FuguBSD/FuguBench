# Implementation register

This register is the one record of implementation state. One row exists for each
unit of the specification. A unit is one design element of one specification
document. The [conventions](index.md#conventions) define the unit IDs. Each row
describes the current state only. A row must not carry a plan name or a
reference to an earlier state. A note can carry the date of a recorded fact.

## States

| State   | Meaning                                                              |
| ------- | -------------------------------------------------------------------- |
| open    | No code implements the unit.                                         |
| partial | Code implements a part of the unit. The note names each absent part. |
| done    | Code implements the full unit. The note links the code or the tests. |
| n-a     | No code can implement the unit. It exists for citation only.         |

The "Done by" column names a phase of the [roadmap](ROADMAP.md), or "—" when no
phase applies.

## Units

| Unit                                      | State   | Done by | Note                                                                                                                                                                                                                                                                         |
| ----------------------------------------- | ------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [CLI-PROGRAM](cli.md#cli-program)         | partial | —       | CLI-PROGRAM-1 needs the pack. [The dispatcher](../lib/App/FuguBench.pm) runs from the checkout with an installed Fugu.                                                                                                                                                       |
| [CLI-VERBS](cli.md#cli-verbs)             | partial | —       | [`version`](../lib/App/FuguBench/Version.pm), and [`worktree`](../lib/App/FuguBench/Worktree.pm) with `create`, `remove`, and `list`. Absent: the subcommand `worktree clone`, and each other verb of the table.                                                             |
| [CLI-CHECKOUT](cli.md#cli-checkout)       | partial | —       | [The walk](../lib/App/FuguBench/Checkout.pm), [the tests](../t/fugubench/checkout.t). Absent: the payload start of CLI-CHECKOUT-1, the configuration error of CLI-CHECKOUT-3, and the `deps` start rule of CLI-CHECKOUT-5.                                                   |
| [CLI-CONFIG](cli.md#cli-config)           | partial | —       | [The reader](../lib/App/FuguBench/Checkout.pm), [the tests](../t/fugubench/checkout.t). [The worktree verb](../lib/App/FuguBench/Worktree.pm) anchors `worktree.base` at the root. Absent: the configuration error that names a key, and the `wiki.` anchor of CLI-CONFIG-2. |
| [CLI-FUGU](cli.md#cli-fugu)               | partial | —       | The verifier and the downloader are absent. They come with the dependency installer.                                                                                                                                                                                         |
| [CLI-SANDBOX](cli.md#cli-sandbox)         | partial | —       | [The table](../lib/App/FuguBench.pm) holds the rows of `version` and `worktree`. The unveil of CLI-SANDBOX-2 waits for the first verb that opens a file. Each other verb adds its row.                                                                                       |
| [CLI-DOCTOR](cli.md#cli-doctor)           | open    | —       | The state report of a checkout.                                                                                                                                                                                                                                              |
| [CLI-CONFORMANCE](cli.md#cli-conformance) | open    | —       | The tests inherited from the Workspace scripts.                                                                                                                                                                                                                              |
| [DEPS-MANIFEST](deps.md#deps-manifest)    | open    | —       | Design from Tooling MK-DEPS and the synced script.                                                                                                                                                                                                                           |
| [DEPS-INSTALL](deps.md#deps-install)      | open    | —       | Design from the synced script.                                                                                                                                                                                                                                               |
| [DEPS-ALIAS](deps.md#deps-alias)          | open    | —       | Design from Tooling SYNC-ALIAS.                                                                                                                                                                                                                                              |
| [DEPS-TIER](deps.md#deps-tier)            | open    | —       | Design from Tooling SYNC-DOWNLOAD, verified in-process.                                                                                                                                                                                                                      |
| [DEPS-KEYS](deps.md#deps-keys)            | open    | —       | Design from Tooling SYNC-KEYS.                                                                                                                                                                                                                                               |
| [DEPS-SUMS](deps.md#deps-sums)            | open    | —       | Design from Tooling SYNC-SUMS.                                                                                                                                                                                                                                               |
| [DEPS-FETCH](deps.md#deps-fetch)          | open    | —       | Every download through Fugu LIB-CURL.                                                                                                                                                                                                                                        |
| [WT-CREATE](worktree.md#wt-create)        | done    | —       | [The verb](../lib/App/FuguBench/Worktree.pm), [the tests](../t/fugubench/worktree-verb.t).                                                                                                                                                                                   |
| [WT-REMOVE](worktree.md#wt-remove)        | done    | —       | [The verb](../lib/App/FuguBench/Worktree.pm), [the tests](../t/fugubench/worktree-verb.t).                                                                                                                                                                                   |
| [WT-LIST](worktree.md#wt-list)            | done    | —       | [The verb](../lib/App/FuguBench/Worktree.pm), [the tests](../t/fugubench/worktree-verb.t).                                                                                                                                                                                   |
| [WT-CLONE](worktree.md#wt-clone)          | open    | —       | Design from Workspace WS-BOOTSTRAP.                                                                                                                                                                                                                                          |
| [WT-SAFETY](worktree.md#wt-safety)        | partial | —       | [Create and remove](../lib/App/FuguBench/Worktree.pm) confine their changes to the base, each child of create leads its own process group, and remove takes each debris of WT-SAFETY-2. Absent: the clone part of WT-SAFETY-1.                                               |
| [WIKI-CLONE](wiki.md#wiki-clone)          | open    | —       | Design from Workspace LIB-WIKI.                                                                                                                                                                                                                                              |
| [WIKI-PAGES](wiki.md#wiki-pages)          | open    | —       | Design from Workspace LIB-PAGES.                                                                                                                                                                                                                                             |
| [WIKI-OPEN](wiki.md#wiki-open)            | open    | —       | The fetch before the count, and the rename.                                                                                                                                                                                                                                  |
| [WIKI-CAPTURE](wiki.md#wiki-capture)      | open    | —       | Design from Workspace LIB-WIKI.                                                                                                                                                                                                                                              |
| [WIKI-STATUS](wiki.md#wiki-status)        | open    | —       | Design from Workspace LIB-WIKI and LIB-CANDIDATE.                                                                                                                                                                                                                            |
| [WIKI-CONFINE](wiki.md#wiki-confine)      | open    | —       | Design from Workspace LIB-WIKI.                                                                                                                                                                                                                                              |
| [HOOK-EVENTS](hooks.md#hook-events)       | open    | —       | Design from Workspace WS-HOOKS and LIB-HOOKS.                                                                                                                                                                                                                                |
| [HOOK-SESSION](hooks.md#hook-session)     | open    | —       | Design from Workspace LIB-HOOKS.                                                                                                                                                                                                                                             |
| [HOOK-WORKTREE](hooks.md#hook-worktree)   | open    | —       | Design from Workspace WS-HOOKS.                                                                                                                                                                                                                                              |
| [HOOK-INSTALL](hooks.md#hook-install)     | open    | —       | The settings writer.                                                                                                                                                                                                                                                         |
| [TRACE-NAME](traces.md#trace-name)        | open    | —       | Design from Workspace WS-SESSION.                                                                                                                                                                                                                                            |
| [TRACE-COLUMNS](traces.md#trace-columns)  | open    | —       | Design from Workspace WS-SESSION.                                                                                                                                                                                                                                            |
| [TRACE-USAGE](traces.md#trace-usage)      | open    | —       | Design from Workspace WS-SESSION.                                                                                                                                                                                                                                            |
| [TRACE-PANEL](traces.md#trace-panel)      | open    | —       | Design from Workspace WS-SESSION.                                                                                                                                                                                                                                            |
| [TRACE-SUB](traces.md#trace-sub)          | open    | —       | Design from Workspace WS-SESSION.                                                                                                                                                                                                                                            |
| [DIST-PACK](dist.md#dist-pack)            | open    | —       | The packed file.                                                                                                                                                                                                                                                             |
| [DIST-ASSETS](dist.md#dist-assets)        | open    | —       | The release assets.                                                                                                                                                                                                                                                          |
| [DIST-SHIM](dist.md#dist-shim)            | open    | —       | The wrapper shim of a consumer.                                                                                                                                                                                                                                              |
| [DIST-INSTALL](dist.md#dist-install)      | open    | —       | The install script and the install verb.                                                                                                                                                                                                                                     |
| [DIST-UPDATE](dist.md#dist-update)        | open    | —       | The verified self-update.                                                                                                                                                                                                                                                    |
| [DIST-KEY](dist.md#dist-key)              | open    | —       | The embedded release keys.                                                                                                                                                                                                                                                   |
| [DIST-VERSION](dist.md#dist-version)      | partial | —       | [The verb](../lib/App/FuguBench/Version.pm), [the tests](../t/fugubench/cli.t). Absent: DIST-VERSION-2, which needs the shim of DIST-SHIM.                                                                                                                                   |

## Update protocol

1. The change that implements a unit, or a part of one, sets the unit state in
   this register in the same change.
2. A `partial` note names each absent rule or part.
3. A `done` note holds at least one relative link to code or to tests.

## Code roots

The drift gate maps each document to the code that implements it.

| Document    | Roots                                            |
| ----------- | ------------------------------------------------ |
| cli.md      | `lib`, `bin`, `t`                                |
| deps.md     | `lib`, `t`                                       |
| worktree.md | `lib`, `t`                                       |
| wiki.md     | `lib`, `t`                                       |
| hooks.md    | `lib`, `t`                                       |
| traces.md   | `lib`, `t`                                       |
| dist.md     | `lib`, `scripts`, `mk`, `.github/workflows`, `t` |

## Retired IDs

| ID  |
| --- |
