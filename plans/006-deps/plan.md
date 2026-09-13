# 006 — The deps verb and the fetch verb

## Status

In progress. Package 1 landed the manifest, the alias expansion, and the dry-run
oracle. Package 2 landed the two tiers, the key set, and the `fetch` verb.
Packages 3 and 4 remain. The Fugu release 0.5.0 carries Fugu LIB-CURL and Fugu
LIB-ED25519, so no package waits on another repository. After the last package,
Tooling ships the shim in place of `scripts/deps` and `scripts/ftp` in a plan of
Tooling (D-09). Each consumer then drops its signify package from the `tool`
environment (DEPS-TIER-8).

Implements: DEPS-MANIFEST. Implements: DEPS-INSTALL. Implements: DEPS-TIER.
Implements: DEPS-SUMS.

Implements: CLI-VERBS. This plan adds the `deps` verb and the `fetch` verb. The
unit stays `partial` until the last verb plan lands.

## Purpose

The synced `scripts/deps` holds 1451 lines, and every consumer carries a copy.
Its downloader is a shell helper, and its signature check runs signify(1). This
plan ports the script into the `deps` verb, with two changes. Every download
goes through Fugu LIB-CURL, and every signature check runs in-process through
Fugu LIB-SIGNIFY. The dry-run trace of the verb equals the trace of the script
over every consumer manifest, so no consumer file changes (D-01).

## Scope

In scope:

- The `deps` verb, `App::FuguBench::Deps`, with its `.pod` sidecar.
- The `fetch` verb, `App::FuguBench::Fetch`, with its `.pod` sidecar.
- The `start` accessor and the two sandbox rows in `App::FuguBench`.
- The conformance fixtures of the thirteen consumers, and the tests.

Out of scope:

- The shim swap in the org pack. Tooling lands it (D-09).
- The manifest edit of each consumer that drops its signify package.
- `Fugu::Curl` and `Fugu::Ed25519`. Fugu plans 009 and 010 land them.

## Constraints that shape the design

**The trace is the oracle, and the quoting function comes with it.** `--dry-run`
prints each command to standard output as `+ ` and the shell-quoted arguments.
The verb copies `_quote` of the script byte for byte. A word passes bare when it
holds word characters, a dot, a slash, a colon, an equals sign, and a dash only.
Every other word, and the empty word, takes single quotes, with `'\''` for a
quote inside. `mkdir -p`, `cp`, `chmod 755`, `tar`, `unzip`, each package
manager, and cpanm run as children through `$app->command`, because the trace
names each one. The trace and the result line of DEPS-INSTALL-10 are the
standard output. Each progress line of the script, and every line of a child,
goes to standard error (CLI-PROGRAM-4).

**Two parts of a download line cannot match byte for byte.** The script names
its random temporary directory and the absolute path of its `ftp` helper there.
The verb downloads in-process, so it prints a download as
`+ fugubench fetch <file> <url>` (DEPS-FETCH-2). The oracle test replaces the
helper path with `fugubench fetch`, and the temporary directory with one token
on each side. It compares the `+ ` lines and changes nothing else. The
implementation adds this sentence to CLI-CONFORMANCE-2 with the code.

**The dry run asks no network.** The script probes the signed manifest of a
stable URL under `--dry-run`, and it stops when no server answers. The verb
reads the manifest, the digest file, and the key set. It prints the download
line of the signify tier without a probe (DEPS-MANIFEST-6). The oracle test
gives the script a stub downloader on a temporary `PATH`, so its probe answers
with no network.

**The downloader reads the status, and never the exit code.** A measured fact:
curl reports the HTTP status through `--write-out` under `--fail`, and a 404
through a redirect exits 56, not 22. Fugu LIB-CURL owns that classification, and
the verb must not re-derive it. The probe reads `status` eq `http` with `code`
404 as the normal absent answer (DEPS-FETCH-3). Every other failed fetch stops
the run with `error`. One `Fugu::Curl` serves the whole run.

**Every signature check runs in-process.** The verb builds
`Fugu::Signify->new(engine => 'perl')`, and each `verify` call names the key
paths, because the object holds no key set. A body-form key becomes a two-line
`.pub` file in the temporary directory, and a URL-form key downloads there and
holds to its digest. A key that fails to load leaves the set with a warning
(DEPS-KEYS-7), and an empty loaded set stops the run with each failure.
`verify($sums, $sig)` runs before the asset download (DEPS-TIER-7), and
`parse_manifest` gives the digest of the file name. One check takes about one
second under the pure-Perl backend, so the verb runs one for each signed entry.

**The digest file goes through the Fugu reader and writer.** `parse_manifest`
rejects a bad line, a short digest, and a duplicate key, as DEPS-TIER-4 wants.
It also rejects a blank line and an empty text, where the script skipped them.
The verb gives an absent file and a file with no line the empty set, and hands
every other file to the reader. It runs the scheme test of DEPS-TIER-5 over the
keys. `write_manifest` sorts the keys, so a second refresh makes a stable diff.

**`deps` has no checkout, and both rows are pledge-only.** The verb reads
`deps/<OS>.txt` relative to the start directory (CLI-CHECKOUT-5), and the
dispatcher builds no checkout for `deps` and `fetch`. Plan 001 adds `fetch` to
the exception of CLI-CHECKOUT-5. Unveil inherits across exec, and the package
managers, cpanm, and a `bin` install write outside every path of a row. So the
`deps` row pledges `stdio rpath wpath cpath proc exec inet dns` and unveils
nothing. The file promises cover the manifest read and the digest file write,
and `proc exec` covers each child. The `bin` install still checks the digest
before the copy (DEPS-TIER). Fugu LIB-CURL runs the downloader as a child, so
the `fetch` row pledges `stdio rpath wpath cpath proc exec inet dns` and unveils
nothing. Plan 001 rewords CLI-SANDBOX-2 and states that `deps` unveils nothing,
so this plan changes no sentence of CLI-SANDBOX-2.

**The exit codes follow the kind of the fault.** A usage error exits 2: an
unknown environment word, `--force` without `--update-sums`, and `--dry-run` or
an environment word with it. A configuration error exits 3: a bad manifest line,
a bad digest line, a file-name key, and a bad key line. A failed download, a
failed check, and a failed child exit 1. No manifest for the operating system
reports on standard error and exits 0.

## The interface contract

### App::FuguBench

`start` returns the `-C` value, or the current directory. The sandbox table
gains the rows `deps` and `fetch`, and the verb table gains both entries.

### App::FuguBench::Deps

`command` returns the entry. The options are `--dry-run`, `--update-sums`,
`--force`, `--os <name>`, and `--arch <name>`. The argument is one environment
word, and `--update-sums` takes none. The body reads `deps/<os>.txt`,
`deps/SHA256.txt`, `deps/KEYS.txt`, and `deps/KEYS.local.txt` under `start`. It
takes `cpanm` from `PATH`, or `$^X` with the downloaded script.

### App::FuguBench::Fetch

`fugubench fetch <file> <url>` calls `Fugu::Curl->new->fetch($url, $file)`, so
the verb swaps the two arguments into the order of the helper. It is silent on
success and returns 0. On a failure it writes `error` to standard error and
returns 1, and no file stays at the destination.

## Files

| File                                     | Change                                               |
| ---------------------------------------- | ---------------------------------------------------- |
| `lib/App/FuguBench.pm`                   | The `start` accessor, the two rows, the two entries  |
| `lib/App/FuguBench.pod`                  | The `start` accessor                                 |
| `lib/App/FuguBench/Deps.pm`              | New: the verb                                        |
| `lib/App/FuguBench/Deps.pod`             | New: the contract                                    |
| `lib/App/FuguBench/Fetch.pm`             | New: the fetch verb                                  |
| `lib/App/FuguBench/Fetch.pod`            | New: the contract                                    |
| `t/fugubench/deps.t`                     | New: the manifest, the aliases, the order, the trace |
| `t/fugubench/deps-conformance.t`         | New: the oracle over the fixtures                    |
| `t/fugubench/deps-tier.t`                | New: the tiers, the keys, the digest file, `fetch`   |
| `t/fugubench/deps-install.t`             | New: the installers over stub package managers       |
| `t/fugubench/deps-sums.t`                | New: `--update-sums` and `--force`                   |
| `t/fugubench/deps/<consumer>/deps/*.txt` | New: the manifests and digest files of each consumer |
| `t/fugubench/deps/fixture/`              | New: a signify key, a signed release, and an archive |
| `spec/cli.md`                            | The sentence of CLI-CONFORMANCE-2                    |
| `spec/STATUS.md`                         | The rows of this plan                                |

The consumers are Fugu, FuguBench, FuguCTX, FuguOracle, FuguPass, FuguSTX,
FuguTTX, FuguVM, FuguWeb, Repositories, Tooling, Website, and Workspace. A
fixture is a copy, so a later manifest change of a consumer does not reach it.

## Work packages

An implementer takes one package at a time, in this order. Each package trims
the citations that it completes, and the last one deletes the plan.

3. **The installers.** `pkg` through the package manager of the platform, `cpan`
   and `dist` through cpanm with the bootstrap, and `bin` into `~/.local/bin`.
   The acceptance check is `t/fugubench/deps-install.t` green, with no real
   install on the host.
4. **The digest refresh.** `--update-sums` with `--force`. The acceptance check
   is `t/fugubench/deps-sums.t` green.

## Tests

Each test runs `bin/fugubench` as a child with `-Ilib`. It sets `HOME` and
`TMPDIR` inside its temporary tree, and it clears `PERL_LOCAL_LIB_ROOT`. A test
of packages 2 to 4 skips when the installed Fugu lacks `Fugu::Curl` or the
`perl` engine. It serves the fixture directory from a loopback HTTP server over
the core `IO::Socket::INET`, as Fugu plan 010 does. The signify fixtures are one
public key and the signatures of one release directory, made once with
signify(1). The organization key never enters a fixture. Stub package managers
and a stub `cpanm` on a temporary `PATH` log their arguments and exit 0, or exit
1 on demand. No test installs anything real.

`t/fugubench/deps.t` covers each error of DEPS-MANIFEST-3, DEPS-MANIFEST-7,
DEPS-MANIFEST-8, DEPS-INSTALL-8, and DEPS-TIER-12, with the line in the message.
It covers the alias resolution: no match, two matches, an unknown system name,
and a placeholder that the URL lacks. It covers the type order, the `HOME`
check, the quoting of a word with a space and a quote, and each usage error. It
covers the report of a missing manifest, with exit 0.

`t/fugubench/deps-conformance.t` runs `scripts/deps --dry-run` from each fixture
directory and `bin/fugubench -C <fixture> deps --dry-run`, with one `--os`,
`--arch`, and environment. The matrix is each fixture, each of the four
environments, Darwin, Linux, and OpenBSD, and `x86_64` and `arm64`. Both
children run under `$^X` and one `PATH` with a stub `curl`, `wget`, and `ftp`,
and no `cpanm`. One pair runs with a stub `cpanm` too. The test skips when
`scripts/deps` is absent from the checkout, which ends CLI-CONFORMANCE-2.

`t/fugubench/deps-tier.t` covers the recorded tier and the signed tier, each
with its mismatch message. It covers the 404 of the probe, a refused connection,
an empty key set, and each key form. It covers a URL-form key with a bad digest
that the next key covers, and a key that verifies nothing. It covers a file-name
key, a duplicate digest line, and a blank line. For `fetch` it covers a 200 that
lands, a 404 that exits 1 and leaves no file, and the argument order.

`t/fugubench/deps-install.t` covers one package command for each platform, with
`apt-get update` first. It covers `cpanm --notest` with and without
`PERL_LOCAL_LIB_ROOT`, and the bootstrap when `cpanm` is absent. It covers a
`bin` from a tar archive, a zip archive, and a plain file, with mode 755. A set
that one entry cannot verify installs nothing, and a child that exits non-zero
stops the run. The result line reaches standard output, and every child line
reaches standard error.

`t/fugubench/deps-sums.t` covers each rule of DEPS-SUMS over the loopback
server. A versioned URL records, a recorded URL stays, and a stable name and a
signed entry skip. A placeholder entry records from the signed manifest, and two
candidates that answer give one line and one warning. `--force` overrides each
skip with its warning, drops the siblings, and drops the file-name key. A run
that records nothing leaves the file, and a missed entry leaves the file and
exits 1.

## Acceptance

- `make check` passes after each package, and the new tests run in `make test`.
- Package 3 sets DEPS-MANIFEST and DEPS-INSTALL to `done`. Package 4 sets
  DEPS-SUMS to `done`, and DEPS-TIER with it: the writer of DEPS-TIER-3 has no
  caller before the digest refresh.
- The change deletes this plan.

## Open questions

None. The module split and the package order follow the synced script, and the
trace equality is the oracle.
