# 007 — The pack, the shim, the install, and the keys

## Status

Work package 1 landed the packer, the `make dist` hook, and
`t/fugubench/pack.t`. Work package 2 landed the `shim` verb, the `install` verb,
their two sandbox rows, and the verb part of `t/fugubench/dist.t`. Package 3
waits on no other plan of this repository. The packer packs the modules that
exist, and the module list test grows with each verb plan.

Fugu v0.5.0 carries the v5.34 floor, so the packed file runs on perl 5.34. The
test runs the pruned `@INC` case on the perl of the suite, and on a perl 5.34 of
the host. Two pieces of work sit in other repositories. FuguBSD/Website serves a
stub at `https://bench.fugubsd.org/get`, and the stub fetches the `install.sh`
of the latest release and runs it. Tooling ships the shim in the org pack
(D-09). The release workflow publishes `fugubench` and `install.sh` under
DIST-ASSETS, in the plan of that unit.

Implements: DIST-INSTALL without DIST-INSTALL-2 and DIST-INSTALL-3. Implements:
DIST-KEY without DIST-KEY-2.

## Purpose

A consumer runs the program through a shim, and the shim needs a packed file to
fetch (D-04). This plan lands the packer, the `shim` verb, the `install` verb,
and the keys module. After it, `make dist` gives a release its packed file and
its install script, and a consumer can pin a release.

## Scope

In scope:

- The packer `scripts/pack`, and the `make dist` hook in `mk/local.mk`.
- The `shim` verb and the `install` verb, in `App::FuguBench::Dist`.
- The keys module `App::FuguBench::Keys`.
- The install script `build/install.sh`.
- The tests of the pack, the two verbs, the script, and the keys.

Out of scope:

- The `update` verb. It lands in plan 008, in the same module.
- The release workflow and its assets, DIST-ASSETS.
- The `/get` address, DIST-INSTALL-3. FuguBSD/Website serves it.

## Constraints that shape the design

**The packer runs after the tarball build.** `mk/perl.mk` runs `$(DIST)` for
`make dist`, and `mk/local.mk` sets `DIST = scripts/pack`. The packer first runs
`scripts/dist` with the same `--version` and `--out` values. This satisfies
DIST-PACK-7 with no change to the synced fragment.

**The staged tree does not survive.** `scripts/dist` removes
`build/App-FuguBench-<version>/` after it writes the tarball. The packer reads
the tarball path from the `Built <path>` line of `scripts/dist`. It extracts the
tarball into a temporary directory and reads the stamped modules there. The
stamp of Fugu REL-VERSION-2 gives the pack its version.

**The Fugu snapshot is the installed Fugu.** `make deps` installs the release
that `deps/<OS>.txt` names (DIST-PACK-6). The packer loads each listed module,
finds its file through `%INC`, and copies the text. The list holds `Fugu`
itself, so the pack carries the stamped `Fugu->VERSION`.

**The module list is explicit, and two tests hold it.** The packer holds the
Fugu module names in one list (DIST-PACK-2). One test starts from the
`use Fugu::` lines of `lib/` and follows each `use` or `require` of a `Fugu::`
module. The pack must hold that closure and nothing more. A second test holds
that no packed module is core in perl 5.34, through `Module::CoreList`
(DIST-PACK-3). Both tests read the module names out of the packed file.

**The pack format is the App::FatPacker scheme, written here.** A `BEGIN` block
installs an `@INC` hook over a hash of module sources, the modules sorted by
name. The text of `bin/fugubench` follows, without its shebang line, and without
its `FindBin` and `lib` lines. Those two lines put `lib/` of a checkout in front
of the pack, and `build/fugubench` sits beside that directory. The file holds no
timestamp and no path of the build host, so two builds of one tree give one byte
sequence (DIST-PACK-4).

**The shim knows its own file.** The `shim` verb reads the sha256 digest of `$0`
with `Digest::SHA`, and the version from `App::FuguBench->VERSION`. In a
checkout the version is `0.0.0`, and no release holds it. The verb then returns
1, and its message names the packed file as the place to run it.

**`install.sh` is the shim with one argument.** The packer runs the packed file
with `shim`, and writes `set -- install` before the shim text. One template
holds the URL, the digest, the downloader order, and the digest tools. The
implementation rewords DIST-INSTALL-1 with the code. The new text: `install.sh`
is an asset that `make dist` writes for its version, and the release workflow
publishes. It is the shim with `install` as its argument list, so the fetch
passes through the shim cache.

**The keys are source.** `App::FuguBench::Keys` holds the release public key
bodies in trust order (DIST-KEY-1), checked in. A test binds the module to
`deps/KEYS.txt`. The implementation rewords DIST-KEY-1 with the code. The new
text: the keys are those of `deps/KEYS.txt` of the org pack, and a test holds
the module to that file.

**Neither verb reads a checkout.** `curl | sh` runs `install` in a home with no
`.toolingrc`, and a fresh clone runs the shim before any install. The two verbs
never call `checkout`, and the dispatcher builds the checkout on the first call
only. Each verb opens a file of its own, so the two rows pledge and unveil, as
plan 001 states. Each row unveils the directory of the running file, the home
paths, and the temporary directory.

## The interface contract

### scripts/pack

`pack [--version <v>] [--out <dir>]` runs `scripts/dist` with the same values,
then writes `<dir>/fugubench` and `<dir>/install.sh`. An empty `--version` value
counts as absent, as in `scripts/dist`. The default out directory is `build`.
The script runs at the repository root, uses core modules alone, and prints
nothing on success.

### App::FuguBench::Dist

`command($verb)` returns the Fugu LIB-CLI entry of `shim` or `install`.

`shim` prints the POSIX shell of DIST-SHIM to standard output, in at most 60
lines. The URL is
`https://github.com/FuguBSD/FuguBench/releases/download/v<version>/fugubench`,
and the digest is the sha256 of the running file. Version `0.0.0` returns 1 with
a message on standard error.

`install` copies the running file to `$HOME/.local/bin/fugubench` with
`Fugu::File->write_atomic` and mode 0755. It makes the directory when absent,
prints the path to standard output, and returns 0. When no `PATH` entry names
the directory, it prints one hint line to standard error.

### App::FuguBench::Keys

`keys` returns the list of `[name, body]` pairs, in the line order of
`deps/KEYS.txt`. A body is the 56 base64 characters of a signify public key.

### The sandbox rows

The `shim` row pledges `stdio` and `rpath`. The `install` row pledges `stdio`,
`rpath`, `wpath`, `cpath`, and `fattr`. Both rows unveil the directory of the
running file `r`, because `shim` reads `$0` and `install` copies it. Both unveil
`~/.local/bin`, `~/.cache/fugubench`, and the temporary directory.

## Files

| File                         | Change                                       |
| ---------------------------- | -------------------------------------------- |
| `scripts/pack`               | New: the packer                              |
| `mk/local.mk`                | `DIST = scripts/pack`                        |
| `lib/App/FuguBench.pm`       | The two verb entries and the two rows        |
| `lib/App/FuguBench/Dist.pm`  | New: the `shim` verb and the `install` verb  |
| `lib/App/FuguBench/Dist.pod` | New: the contract                            |
| `lib/App/FuguBench/Keys.pm`  | New: the release keys                        |
| `lib/App/FuguBench/Keys.pod` | New: the contract                            |
| `t/fugubench/pack.t`         | New: the bytes, the pruned `@INC`, the list  |
| `t/fugubench/dist.t`         | New: the shim, the install, and `install.sh` |
| `t/fugubench/keys.t`         | New: the module against `deps/KEYS.txt`      |
| `spec/dist.md`               | The rewordings of DIST-INSTALL-1, DIST-KEY-1 |
| `spec/STATUS.md`             | The rows of this plan                        |

## Work packages

1. The packer, `mk/local.mk`, and `t/fugubench/pack.t`. Acceptance: `make dist`
   writes `build/fugubench`, and `pack.t` passes.
2. The two verbs, the rows, and the verb part of `t/fugubench/dist.t`.
   Acceptance: `dist.t` passes without the `install.sh` case.
3. The keys module, `t/fugubench/keys.t`, the `install.sh` output of the packer
   with its case in `dist.t`, and the two rewordings. Acceptance: `make check`
   passes, and the register rows are set.

## Tests

Each test runs the packer, or the packed file, as a child. A test writes only
inside its temporary tree, sets `HOME` to that tree, and never reads the
operator home. A test that builds a pack passes `--out` and a test version, so
`build/` stays untouched.

`t/fugubench/pack.t` covers:

- Two packs of one tree are byte-equal.
- The packed file starts with `#!/usr/bin/env perl`.
- Under a pruned `@INC` of `privlibexp` and `archlibexp`, with no `PERL5LIB`,
  `require Fugu` fails, and the packed file runs `version` and `--help` with
  exit 0. The version line names the test version and `Fugu->VERSION`.
- The packed modules equal the closure of `lib/` over the installed Fugu, plus
  every module under `lib/App/FuguBench/`.
- No packed module is core in perl 5.34.
- The packed file beside a `lib/App/FuguBench.pm` of a checkout loads its own
  module, and not that file.

`t/fugubench/dist.t` covers, with a pack in the temporary tree:

- `shim` prints at most 60 lines, and `sh -n` accepts them. The text holds the
  URL of the test version and the digest of the pack.
- `bin/fugubench shim` in the checkout exits 1 with a message.
- A stub downloader on a temporary `PATH` serves the pack. The shim caches the
  file with mode 755, passes the arguments through, and exits with the code of
  the program. A second run uses the cache and no downloader.
- With a stub that serves another file, the shim deletes the download, prints
  both digests, and exits non-zero.
- With `FUGUBENCH` set, the shim runs that file and no downloader.
- With no downloader on `PATH`, the shim names `curl`, `wget`, and `ftp`, and
  exits non-zero.
- `install` writes `$HOME/.local/bin/fugubench` byte-equal to the running file,
  with mode 755, prints the path, and hints when `PATH` lacks the directory.
- `sh install.sh` with the stub downloader installs the pack into `$HOME`.

`t/fugubench/keys.t` covers:

- Each body-form line of `deps/KEYS.txt` equals the pair of the module at the
  same position.
- With `FUGUBENCH_NETWORK` set, each URL-form line fetches the key file with
  `curl`. The case holds it to the digest, and compares its second line to the
  body. Without the variable the case skips, so `make test` reads no network.
- The module holds no pair that the file lacks.

## Acceptance

- `make check` passes, and `make dist` writes the tarball, `build/fugubench`,
  and `build/install.sh`.
- `spec/STATUS.md` sets DIST-SHIM to `done`. DIST-PACK and CLI-PROGRAM are
  `done` already, and no later package changes them. It sets DIST-INSTALL to
  `partial`, and the note names DIST-INSTALL-3 and FuguBSD/Website. It sets
  DIST-KEY to `partial`, and the note names DIST-KEY-2 until `update` lands.
  CLI-VERBS and CLI-SANDBOX stay `partial`, and each note drops the two verbs.
- The change deletes this plan.

## Open questions

None. The packer, the pack format, and the shim shape follow D-02, D-03, and
D-04.
