# 008 — The release and the update verb

## Status

Proposed. It lands last, after each wait below. Nothing lands now.

- Tooling: an asset input of the shared workflow `perl-release.yml`, and the
  perl floor of `scripts/dist`.
- Repositories: the `release_repos` entry of FuguBench.
- Fugu: a release that carries Fugu LIB-CURL and Fugu LIB-ED25519.
- Website: the `/get` address of DIST-INSTALL-3.

Implements: DIST-ASSETS. Implements: DIST-UPDATE. Implements: DIST-KEY. The
`update` verb verifies with the embedded keys alone, so DIST-KEY-2 holds with
this plan.

Implements: CLI-VERBS. This plan lands the `update` verb, the last verb of the
table.

Implements: CLI-SANDBOX. This plan adds the row of `update`, the last row of the
table.

## Purpose

A release exists so that a consumer runs a pinned program, and an operator
updates one. The shared workflow of Tooling publishes the tarballs and the
signed manifest for every Perl distribution of the organization. This plan calls
that workflow with the two extra assets of D-03. It lands the verb that fetches
a release and verifies it in-process (D-05).

## Scope

In scope:

- The release caller `.github/workflows/release.yml`.
- The `update` verb, `App::FuguBench::Update`, with its sandbox row.
- The loopback tests of the verb, with a committed fixture key pair.
- The first tag, `v0.1.0`.

Out of scope:

- The pack, the shim, `install.sh`, the `install` verb, and the keys module.
  Each one exists already.
- The shared workflow of Tooling, and the PAUSE secrets of Repositories.
- The `/get` page of FuguBSD/Website.

## Constraints that shape the design

**One verb, one module.** The verb table of CLI-VERBS lists `update` as a verb
of its own, and plan 001 maps each verb to one module. A subcommand of a `Dist`
module would add a dispatch level and a shared sandbox row for verbs with
different promises. The sibling module `App::FuguBench::Update` is the fewer
parts.

**The caller adds no step.** The shared workflow runs `make dist` in the tree of
the caller and publishes files under `build/`. So `make dist` leaves
`build/fugubench` and `build/install.sh`, and the caller names them in the asset
input. The caller holds the two routes and the inputs, as the caller of Fugu
does.

**The manifest is the version.** The versioned tarball name in `SHA256`,
`App-FuguBench-<version>.tar.gz`, is the version of the release. The running
version is the one that `version` prints, and `0.0.0` in a checkout.

**Two checks, one library.** The verb calls `verify` of Fugu LIB-SIGNIFY on the
manifest before it fetches the packed file, as DIST-UPDATE-1 orders. After the
fetch it calls `verify_manifest` with the temporary path, so the digest check
comes from the same module. `Fugu::Signify->new` takes key file paths. So the
verb writes each `[name, body]` pair of `App::FuguBench::Keys` as one signify
public key file in the temporary directory, in trust order.

**The release must carry a signature.** Without a key slot, the shared workflow
publishes no manifest (Tooling WFL-SIGN-7), and the verb finds nothing to
verify. The first tag needs the slot and the key in `deps/KEYS.txt` of the org
pack (DIST-KEY-1).

**The tests need a base URL.** A test serves a release on the loopback. The
environment variable `FUGUBENCH_RELEASE_URL` replaces
`https://github.com/FuguBSD/FuguBench` in the two download paths. The variable,
not an option: the usage stays the two options that DIST-UPDATE names. The shim
takes its developer override from the environment too (DIST-SHIM-2). The
implementation adds this sentence to DIST-UPDATE-1 with the code.

**The running file can sit outside `~/.local/bin`.** The verb replaces the
running file where it is. The row of `update` unveils nothing, so no path list
bounds the write. Plan 001 names `update` among the verbs with a network promise
in CLI-SANDBOX-2, so this plan changes no rule of cli.md.

## The interface contract

### The release caller

`.github/workflows/release.yml` runs on a push of a `v*` tag, and on a dispatch
with a `version` input. The dispatch route makes the tag first, as the caller of
Fugu does. The release job calls
`FuguBSD/Tooling/.github/workflows/perl-release.yml@main` with
`dist: App-FuguBench`, `name: FuguBench`, `pause: true`, the tag of a dispatch,
and the asset input with `build/fugubench` and `build/install.sh`. The
`install-note` holds the command of DIST-INSTALL-3. The caller passes
`secrets: inherit` and keeps `permissions: contents: write`.

### The update verb

`App::FuguBench::Update->command` returns the entry of the Fugu LIB-CLI table.
The usage is `update [--version <tag>] [--allow-downgrade]`. The verb reads no
checkout and calls no `checkout` method.

The release directory is
`https://github.com/FuguBSD/FuguBench/releases/latest/download/`, or
`https://github.com/FuguBSD/FuguBench/releases/download/<tag>/` with
`--version`. A tag must match `v<MAJOR>.<MINOR>.<PATCH>`, or the verb exits 2.
`FUGUBENCH_RELEASE_URL` replaces the host and repository part.

The verb runs these steps, in order, and stops at the first failure:

1. It resolves the running file through `Cwd::realpath` of `$0`. A file under
   `~/.cache/fugubench/` is a refusal that names the Tooling sync as the path to
   a new version (DIST-UPDATE-3).
2. It fetches `SHA256` and `SHA256.sig` into a temporary directory through
   `fetch` of Fugu LIB-CURL. A `status` of `http` with `code` 404 names the tag
   as absent.
3. It writes the keys of `App::FuguBench::Keys` into the temporary directory and
   verifies the manifest with
   `Fugu::Signify->new(engine => 'perl', keys => \@paths)`. The consumer keys of
   DEPS-KEYS never enter (DIST-KEY-2).
4. It reads the version from the versioned tarball name in the manifest. A
   version below the running one is a refusal without `--allow-downgrade`
   (DIST-UPDATE-2).
5. It fetches `fugubench` into the temporary directory and calls
   `verify_manifest` with `files => { fugubench => $tmp }`.
6. It replaces the running file through `Fugu::File->write_atomic` with
   `mode => 0755`, and prints `fugubench <version>` to standard output.

Every failure returns 1 with the reason on standard error.

### The sandbox row

The row of `update` pledges `stdio rpath wpath cpath fattr proc exec inet dns`.
The file promises serve the replace, and `proc exec` serves the downloader child
of Fugu LIB-CURL. It unveils nothing, as plan 001 states for a verb with a
child.

## Files

| File                            | Change                                          |
| ------------------------------- | ----------------------------------------------- |
| `.github/workflows/release.yml` | New: the release caller                         |
| `lib/App/FuguBench/Update.pm`   | New: the update verb                            |
| `lib/App/FuguBench/Update.pod`  | New: the contract                               |
| `lib/App/FuguBench.pm`          | The `update` entry and its sandbox row          |
| `t/fugubench/update.t`          | New: the loopback tests                         |
| `t/fugubench/fixtures/update/`  | New: the fixture key pair and two release trees |
| `.gitleaksignore`               | The fixture secret key, when the gate flags it  |
| `spec/dist.md`                  | The environment sentence of DIST-UPDATE-1       |
| `spec/STATUS.md`                | The rows of this plan                           |

## Work packages

1. **The update verb with the loopback tests.** Lands `App::FuguBench::Update`,
   its sidecar, its sandbox row, the fixtures, and `t/fugubench/update.t`.
   Acceptance: `make check` passes, and the test runs, not skips, on the perl of
   the host with the released Fugu.
2. **The release caller and the first tag.** Lands `release.yml`, after the
   Tooling input exists. Then Repositories adds the name and applies, and a
   maintainer pushes `v0.1.0`. Acceptance: the release holds the six assets of
   DIST-ASSETS-1, `SHA256` names all six, and PAUSE lists `App::FuguBench`.

## Tests

`t/fugubench/update.t` starts a loopback HTTP server on `IO::Socket::INET` in a
child process. The server maps `/releases/latest/download/<file>` to the fixture
tree `v1.3.0`, and `/releases/download/v1.1.0/<file>` to the fixture tree
`v1.1.0`. Each other path returns 404. Each tree holds `SHA256`, `SHA256.sig`,
and a small `fugubench` file. The `SHA256` file names the six assets of
DIST-ASSETS-1, and the fixture key signs it. The key pair comes from
`signify -G -n` once, and the test never touches the organization key.

The test copies `bin/fugubench` into its temporary tree and runs the copy as a
child, with `-Ilib` and with `HOME` inside the tree. A temporary library
directory comes first in `@INC`. It holds a copy of `lib/App/FuguBench.pm`
stamped with `our $VERSION = '1.2.0'`, as the dist build stamps it. It also
holds a copy of `App::FuguBench::Keys` with the fixture public key in place of
the organization keys. `FUGUBENCH_RELEASE_URL` names the server. The test skips
when the installed Fugu lacks Fugu LIB-CURL or Fugu LIB-ED25519, or when `PATH`
holds none of `curl`, `wget`, and `ftp`.

Cases:

- A good update replaces the copy with the `v1.3.0` file, mode 755, and prints
  `fugubench 1.3.0`.
- The `SHA256.sig` of `v1.1.0` served beside the `SHA256` of `v1.3.0` fails with
  a signature reason, and the copy is unchanged.
- A `fugubench` of other bytes under the good manifest fails with the expected
  and the computed digest, and the copy is unchanged.
- `--version v1.1.0` without the flag fails with both versions in the reason.
- `--version v1.1.0 --allow-downgrade` replaces the copy and prints
  `fugubench 1.1.0`.
- A copy under `<HOME>/.cache/fugubench/1.2.0/` fails with the Tooling sync in
  the reason, before any fetch.
- `--version v9.9.9` fails with the tag as absent, and `--version 1.3.0`
  exits 2.

## Acceptance

- `make check` passes, and `t/fugubench/update.t` runs on the perl of the host
  with the released Fugu.
- The `v0.1.0` release holds `fugubench`, `App-FuguBench-0.1.0.tar.gz`,
  `App-FuguBench.tar.gz`, `install.sh`, `SHA256`, and `SHA256.sig`. The manifest
  names all six.
- From a checkout, `make dist` and `build/fugubench install` put the pack in
  `~/.local/bin`. Then `fugubench update` replaces it with the release, and
  `fugubench version` prints `0.1.0`.
- `spec/STATUS.md` sets DIST-ASSETS and DIST-UPDATE to `done`, with a link to
  `release.yml` and to the test. It sets DIST-KEY to `done`, because `update`
  completes DIST-KEY-2. It sets CLI-VERBS and CLI-SANDBOX to `done`, because
  this plan adds the last verb and the last row.
- The change deletes this plan.

## Open questions

None. Plan 001 adds `update` to the verbs of CLI-CHECKOUT-5 that read no
checkout, so the verb runs from `~/.local/bin` in any directory.
