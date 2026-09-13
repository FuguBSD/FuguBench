# 009 — The website and the install address

## Status

Proposed. It lands on its own, and it waits on no plan of this repository. It
changes no module and no verb, so it lands before the code of plan 001 or after
it.

Plan 008 of this repository waits on this plan. The wait list of plan 008 names
the `/get` address of DIST-INSTALL-3, because its release caller prints that
address in the install note. The implementation of this plan drops that wait
item. It also gives plan 008 the install command of the front page, because no
release exists until plan 008 tags one.

Two facts hold today, and this plan needs no work on them. The DNS record of
`bench.fugubsd.org` resolves to the GitHub Pages addresses. FuguBSD/Repositories
holds the `github_repository_pages` resource with that cname on `main`.

Two follow-on items belong to other repositories, and not to this plan.
FuguBSD/Website lists each project website on its front page, and it gains the
FuguBench entry after this site goes live. The pull request 4 of FuguBSD/Website
holds that entry. The operator runs the OpenTofu apply of FuguBSD/Repositories.

Implements: DIST-INSTALL without DIST-INSTALL-1 and DIST-INSTALL-2. The code of
those two rules exists, and this plan is the owner of DIST-INSTALL-3. The
implementation rewords that rule with the code.

Defers: DIST-ASSETS. The stub fetches the `install.sh` of the latest release,
and plan 008 publishes that asset.

## Purpose

FuguBench is the ninth project of the organization, and the only one with no
website. Every other project holds a site at a subdomain of `fugubsd.org`.
fuguweb(1) builds a site from `.fuguwebrc` and `web/`, and a thin caller of the
shared `web-publish.yml` workflow of Tooling deploys it to GitHub Pages.
FuguBench takes `bench.fugubsd.org`.

The site also carries the install address, `https://bench.fugubsd.org/get`. That
address is the reason that plan 008 waits. A release note points a reader at one
stable command, and no release changes the address that it prints.

## Scope

In scope:

- `.fuguwebrc`, the description of a two-page site.
- `web/index.body.html` and `web/404.body.html`, the two page bodies.
- `web/robots.txt`, the crawler file that each sibling site holds.
- `web/get`, the stub of the install address.
- `.github/workflows/publish.yml`, the caller of the shared workflow.
- The `sync.pack web` line of `.toolingrc`, and the two files that the web pack
  syncs into `web/`.
- `t/fugubench/get.t`, and the test glob of `mk/local.mk`.
- The rewording of DIST-INSTALL-3 in `spec/dist.md`, and the register row.
- The wait item and the scope of `plans/008-release-update/plan.md`.

Out of scope:

- A manuals page. `lib/` holds no module today, so `.fuguwebrc` holds no
  `modules` block, and `publish.yml` watches no POD path. The change that lands
  the first module adds both.
- The install command of the front page. Plan 008 adds it with the first
  release, so the page states no command that fails.
- The DNS record, and the Pages resource of FuguBSD/Repositories.
- The front-page entry of FuguBSD/Website.

## Constraints that shape the design

**The site is static.** GitHub Pages answers with the files that fuguweb(1)
built, and it runs no code of this repository. So a redirect at the server is
not available, and the address must hold a file.

**The asset needs no entry.** fuguweb(1) copies each plain file of the source
directory to the output as it stands. `web/get` is no body fragment, no Markdown
file, and no dot file, so it is an asset. That rule belongs to FuguWeb, and
`.fuguwebrc` names no entry for the file.

**The stub holds no version and no digest.** A static site cannot follow a
moving release. The stub reads
`https://github.com/FuguBSD/FuguBench/releases/latest/download/install.sh`, and
GitHub resolves the latest release at the moment of the fetch. So no release of
FuguBench needs a change of the website. The script that the stub runs holds the
version, the URL, and the digest of its own release (DIST-INSTALL-1).

**The stub assigns the fetch, and then runs it.** A pipe of `curl` into `sh`
hides a failed fetch. `sh` reads an empty script and exits 0, and the reader
sees a successful install. The variable holds the whole script before `sh`
starts, so no failed fetch reaches `sh`.

**The trust root is HTTPS to GitHub (D-05).** The `install.sh` that the stub
runs verifies every later download against the release key of the organization.
The stub needs no key, and it holds no verification of its own.

**The downloader order follows the platform.** OpenBSD base holds `ftp` and no
`curl`, and OpenBSD is the production platform of the organization. So the stub
takes the first of `curl`, `wget`, and `ftp` on `PATH`.

**The cname is not a file here.** FuguBSD/Repositories holds the
`github_repository_pages` resource, so `web/` holds no `CNAME` file.

## The interface contract

The reworded rule holds the address and the stub. This plan holds the shape of
the file.

### The rewording of DIST-INSTALL-3

The implementation rewords DIST-INSTALL-3 with the code. The new text: the
stable address of the install script is `https://bench.fugubsd.org/get`, and the
published command is `curl -fsSL https://bench.fugubsd.org/get | sh`. The
website of this repository serves a stub at that address. The stub must fetch
the `install.sh` of the latest release into a variable, and it must then run
that variable.

### web/get

The file is POSIX shell. It reads no option and takes no argument. It runs these
steps, in order, and it stops at the first failure:

1. It takes the first of `curl`, `wget`, and `ftp` on `PATH`. With none of the
   three, it names the three commands on standard error and exits 1.
2. It fetches the `install.sh` of the latest release into a variable, and it
   follows each redirect. The latest-release path answers with a redirect, so
   `curl` takes `-fsSL`.
3. A failed fetch, or an empty text, prints a reason on standard error and
   exits 1.
4. It prints the variable on the standard input of `sh`, and it exits with the
   code of `sh`.

The file must fit in 30 lines. A visitor reads the stub before the visitor runs
it, and one screen holds the whole file.

### The site

`.fuguwebrc` names the site `FuguBench`. It holds one nav entry for
`index.html`, the page `index.html` with `index.body.html`, and the unlinked
page `404.html` with `404.body.html`. The site of FuguPass holds the same four
blocks.

The front page states what the program does, and the properties that set the
design apart. It points at the source repository, the specification, and the
releases. `web/CLAUDE.md` of the web pack holds the rules of the page. The 404
page points at the front page of this site.

### The workflow caller

`.github/workflows/publish.yml` runs on a push to `main` that changes
`.fuguwebrc`, a file under `web/`, or the caller itself. It holds the
permissions `contents: read`, `pages: write`, and `id-token: write`, and the
concurrency group `pages` with no cancel. Its one job calls
`FuguBSD/Tooling/.github/workflows/web-publish.yml@main`. The caller of Fugu
holds the same shape.

## Files

| File                               | Change                                   |
| ---------------------------------- | ---------------------------------------- |
| `.toolingrc`                       | The `sync.pack web` line                 |
| `web/CLAUDE.md`                    | New: the synced rules of the web pack    |
| `web/footer.body.html`             | New: the synced footer of the web pack   |
| `.fuguwebrc`                       | New: the site description                |
| `web/index.body.html`              | New: the body of the front page          |
| `web/404.body.html`                | New: the body of the not-found page      |
| `web/robots.txt`                   | New: the crawler file                    |
| `web/get`                          | New: the stub of the install address     |
| `.github/workflows/publish.yml`    | New: the caller of the shared workflow   |
| `t/fugubench/get.t`                | New: the tests of the stub               |
| `mk/local.mk`                      | The `t/fugubench/*.t` test glob          |
| `spec/dist.md`                     | The rewording of DIST-INSTALL-3          |
| `spec/STATUS.md`                   | The DIST-INSTALL row, and the `web` root |
| `plans/008-release-update/plan.md` | The wait item and the scope              |

## Work packages

1. **The site.** Lands the `sync.pack web` line, the two synced files,
   `.fuguwebrc`, the two bodies, `robots.txt`, and `publish.yml`. Acceptance:
   `fuguweb build --out web/build` and `fuguweb check --out web/build` pass, and
   `make check` passes. The drift gate accepts the two synced files.
2. **The install address.** Lands `web/get`, `t/fugubench/get.t`, and the test
   glob. Acceptance: `make check` passes, and each case of `get.t` runs.
3. **The specification and the register.** Lands the rewording of
   DIST-INSTALL-3, the register row, the `web` code root of `dist.md`, and the
   two edits of plan 008. Acceptance: `make spec-check` and `make check` pass.

## Tests

`t/fugubench/get.t` runs `web/get` as a child of `sh`, with a temporary `PATH`
that holds one stub downloader. The test reads no network, and it writes inside
its temporary tree only. It skips when `web/get` is absent, so the release
tarball passes. Cases:

- `sh -n` accepts the file, and the file holds at most 30 lines.
- A stub `curl` prints a script that writes a marker file. The child exits 0,
  and the marker file holds the text of the script.
- A stub `curl` prints nothing and exits 1. The child exits non-zero, and no
  marker file exists. This case is the mutation of the pipe rule: a pipe of the
  downloader into `sh` exits 0 here.
- A stub `curl` prints nothing and exits 0. The child exits non-zero.
- A stub `curl` prints a script that exits 3. The child exits 3.
- The stub `curl` records its arguments. The recorded URL equals
  `https://github.com/FuguBSD/FuguBench/releases/latest/download/install.sh`.
- The temporary `PATH` holds none of the three downloaders. The child names
  `curl`, `wget`, and `ftp`, and it exits non-zero.

## Acceptance

- `make check` passes, and `fuguweb check --out web/build` reports no finding.
- After the merge, the run of `publish.yml` is green. Then
  `https://bench.fugubsd.org/` answers with the front page, and
  `https://bench.fugubsd.org/get` answers with the bytes of `web/get`.
- `spec/STATUS.md` sets DIST-INSTALL to `done`, because the two other rules hold
  already. The "Code roots" table of `dist.md` gains `web`.
- The change deletes this plan.

## Open questions

None. The site follows the shape of the eight sibling sites, and D-05 holds the
trust root of the first fetch.
