# 008 — The release and the update verb

## Status

Each wait of this plan is clear. The shared workflow `perl-release.yml` holds
its asset input. Repositories holds the `release_repos` entry of FuguBench. The
released Fugu carries Fugu LIB-CURL and Fugu LIB-ED25519.

Work package 1 landed the `update` verb, its sandbox row, and its tests. Work
package 2 lands now.

Implements: DIST-ASSETS.

## Purpose

A release exists so that a consumer runs a pinned program, and an operator
updates one. The shared workflow of Tooling publishes the tarballs and the
signed manifest for every Perl distribution of the organization. This plan calls
that workflow with the two extra assets of D-03.

## Scope

In scope:

- The release caller `.github/workflows/release.yml`.
- The first tag, `v0.1.0`.
- The install command of the front page, in `web/index.body.html`.

Out of scope:

- The pack, the shim, `install.sh`, the `install` verb, the `update` verb, and
  the keys module. Each one exists already.
- The shared workflow of Tooling, and the PAUSE secrets of Repositories.

## Constraints that shape the design

**The caller adds no step.** The shared workflow runs `make dist` in the tree of
the caller and publishes files under `build/`. So `make dist` leaves
`build/fugubench` and `build/install.sh`, and the caller names them in the asset
input. The caller holds the two routes and the inputs, as the caller of Fugu
does.

**The release must carry a signature.** Without a key slot, the shared workflow
publishes no manifest (Tooling WFL-SIGN-7), and the `update` verb finds nothing
to verify. The first tag needs the slot and the key in `deps/KEYS.txt` of the
org pack (DIST-KEY-1).

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

## Files

| File                            | Change                  |
| ------------------------------- | ----------------------- |
| `.github/workflows/release.yml` | New: the release caller |
| `web/index.body.html`           | The install command     |
| `spec/STATUS.md`                | The row of DIST-ASSETS  |

## Work packages

2. **The release caller and the first tag.** Lands `release.yml`, after the
   Tooling input exists. Then Repositories adds the name and applies, and a
   maintainer pushes `v0.1.0`. Acceptance: the release holds the six assets of
   DIST-ASSETS-1, `SHA256` names the four that the workflow digests, and PAUSE
   lists `App::FuguBench`.

## Acceptance

- The `v0.1.0` release holds `fugubench`, `App-FuguBench-0.1.0.tar.gz`,
  `App-FuguBench.tar.gz`, `install.sh`, `SHA256`, and `SHA256.sig`. The manifest
  names the two tarballs, the packed file, and the install script. It names
  neither itself nor its own signature.
- From a checkout, `make dist` and `build/fugubench install` put the pack in
  `~/.local/bin`. Then `fugubench update` replaces it with the release, and
  `fugubench version` prints `0.1.0`.
- `spec/STATUS.md` sets DIST-ASSETS to `done`, with a link to `release.yml`.
- The change deletes this plan.

## Open questions

None.
