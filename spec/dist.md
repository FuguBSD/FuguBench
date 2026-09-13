# The pack, the release, and the shim

This document specifies how the program reaches a host. It covers the packed
file, the release assets, the wrapper shim of a consumer, and the install
script. It also covers the update, the embedded keys, and the version.

<a id="dist-pack"></a>

## The pack

- **DIST-PACK-1** — `make dist` must build the CPAN tarball of the perl pack and
  the packed file `fugubench`. The packed file holds `bin/fugubench`, every
  module under `lib/App/FuguBench/`, and the closure of the Fugu modules that
  CLI-FUGU names.
- **DIST-PACK-2** — The packer must take an explicit module list, and never a
  trace of one run. A trace follows one verb and misses the rest.
- **DIST-PACK-3** — A core module must never enter the pack. The host perl holds
  it.
- **DIST-PACK-4** — The pack must be reproducible: the same sources give the
  same bytes. The packer must sort the modules, and it must write no timestamp
  and no path of the build host.
- **DIST-PACK-5** — The packed file must start with `#!/usr/bin/env perl`, and
  it must run under perl 5.34 with core modules alone. A test must run the
  packed file with a pruned `@INC`, as Fugu ARC-COREPERL does for the library.
- **DIST-PACK-6** — The Fugu snapshot comes from the released Fugu that the
  manifest of this repository names. The pack must record that Fugu version, and
  `fugubench version` prints it beside its own.
- **DIST-PACK-7** — The packer must be a core-only Perl script of this
  repository, and `make dist` must run it after the tarball build. No build-time
  CPAN module is needed, and the packer never runs on a consumer host.

<a id="dist-assets"></a>

## The release assets

- **DIST-ASSETS-1** — A release is deliberate: a tag `v<MAJOR>.<MINOR>.<PATCH>`,
  through the shared release workflow of Tooling. The workflow must publish
  `fugubench`, `App-FuguBench-<version>.tar.gz`, `App-FuguBench.tar.gz`,
  `install.sh`, `SHA256`, and `SHA256.sig`.
- **DIST-ASSETS-2** — The `SHA256` manifest must name each asset by file name,
  and the release key of the organization must sign it. A consumer verifies the
  manifest through DEPS-TIER-7.
- **DIST-ASSETS-3** — The workflow must publish the tarball to PAUSE, so
  `cpanm App::FuguBench` works.
- **DIST-ASSETS-4** — The version comes from the tag, as Fugu REL-VERSION says,
  and the packed file carries it.

<a id="dist-shim"></a>

## The wrapper shim

A consumer holds a wrapper shim at `scripts/fugubench`. The org pack of Tooling
syncs it (D-09), and the make fragment calls it in place of `scripts/deps`. The
shim is the pin, because it holds the version that it runs. A new version is a
Tooling sync, as a new `scripts/deps` is today.

- **DIST-SHIM-1** — `fugubench shim` must print the shim to standard output. The
  shim is POSIX shell. It holds the download URL and the sha256 digest of the
  packed file of the version that printed it.
- **DIST-SHIM-2** — When `FUGUBENCH` names an executable in the environment, the
  shim must run it and nothing else. A developer points it at `bin/fugubench` of
  a checkout.
- **DIST-SHIM-3** — The shim must run the cached file
  `~/.cache/fugubench/<version>/fugubench` when it exists. Otherwise it must
  download the packed file with the first of `curl`, `wget`, and `ftp` on
  `PATH`. It must hold the file to the digest with `sha256`, `shasum -a 256`, or
  `sha256sum`. It must move the file into the cache atomically, with mode 755,
  and then run it.
- **DIST-SHIM-4** — A failed check must delete the download, print the expected
  and the computed digest, and exit non-zero.
- **DIST-SHIM-5** — The shim must pass every argument through unchanged, and it
  must exit with the code of the program.
- **DIST-SHIM-6** — The shim must fit in 60 lines, so a reader audits it in one
  screen.
- **DIST-SHIM-7** — Without a downloader on `PATH`, the shim must name the three
  commands and exit non-zero.

<a id="dist-install"></a>

## The install script and the install verb

- **DIST-INSTALL-1** — `install.sh` is an asset that `make dist` writes for its
  version, and the release workflow publishes. It must be the shim of DIST-SHIM
  with `install` as its argument list. The download, the digest check, and the
  cache are then those of the shim. A build of a tree with no tag carries the
  version `0.0.0`. No release holds that version, so such a build must write no
  install script.
- **DIST-INSTALL-2** — `fugubench install` must copy the running program to
  `~/.local/bin/fugubench` with mode 755, atomically, and print the path. It
  must print a hint when `PATH` lacks the directory.
- **DIST-INSTALL-3** — The stable address of the install script is
  `https://fugubsd.org/get`, and the published command is
  `curl -fsSL https://fugubsd.org/get | sh`. FuguBSD/Website serves the script
  of the latest release at that address.

<a id="dist-update"></a>

## Update

- **DIST-UPDATE-1** — `fugubench update [--version <tag>]` must fetch `SHA256`
  and `SHA256.sig` of the latest release, or of the named tag. It must verify
  the signature with the embedded keys (DIST-KEY). It must then fetch the packed
  file, hold it to the manifest digest, and replace the running file atomically.
- **DIST-UPDATE-2** — The verb must refuse a version below the running one,
  unless `--allow-downgrade` is set. A replay of an earlier release is the
  attack that the refusal stops.
- **DIST-UPDATE-3** — The verb must refuse to replace a file under the shim
  cache. It must name the Tooling sync as the path to a new version there. The
  cache path carries the version, so a replaced file would fail the digest of
  the shim.

<a id="dist-key"></a>

## The embedded keys

- **DIST-KEY-1** — The program must embed the release public keys of the
  organization, in trust order, in one module. The keys are those of
  `deps/KEYS.txt` of the org pack, and a test must hold the module to that file.
- **DIST-KEY-2** — `update` verifies with the embedded keys alone. `deps`
  verifies with the keys of the consumer, per DEPS-KEYS, and never with the
  embedded keys. A consumer decides what it trusts.
- **DIST-KEY-3** — A key rotation is a release of the program. The old key stays
  in the list for one release after the new key enters it. An operator one
  release behind can then still update.

<a id="dist-version"></a>

## The version

- **DIST-VERSION-1** — `fugubench version` must print `fugubench <version>` and
  the Fugu version of the snapshot on one line. In a checkout with no tag, the
  version is `0.0.0`.
- **DIST-VERSION-2** — A consumer gate can run the shim with `version`, so one
  command tells the pinned release.
