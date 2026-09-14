# Install FuguBench

FuguBench runs on core Perl v5.34 or later. One packed Perl file holds every
verb, and it carries the Fugu modules that it uses, so it loads no CPAN module.
There are three install flows: the install script, CPAN with cpanm, and a
checkout. A FuguBSD repository installs nothing, because it runs the program
through a wrapper shim.

## With the install script

```sh
curl -fsSL https://bench.fugubsd.org/get | sh
```

The script downloads the packed file of the latest release, holds it to its
sha256 digest, and copies the program to `~/.local/bin/fugubench`. It prints a
hint when `PATH` does not hold that directory.

Then `fugubench update` replaces the program with a later release. The verb
verifies the release against the signify public keys that the program embeds. It
refuses a release below the running version, unless the operator passes
`--allow-downgrade`.

## From CPAN

Every release goes to CPAN as the
[App-FuguBench](https://metacpan.org/dist/App-FuguBench) distribution. The
distribution names Fugu as a prerequisite, so one name installs both:

```sh
cpanm --notest App::FuguBench
```

The cpanm flow installs the modules and the `fugubench` program. It installs no
packed file. Run cpanm again to take a later release.

## From a checkout

```sh
git clone https://github.com/FuguBSD/FuguBench.git
cd FuguBench
make deps
```

`make deps` installs the latest
[Fugu release](https://github.com/FuguBSD/Fugu/releases/latest), `signify`, and
`gitleaks`. The checkout then runs `bin/fugubench`, and `make check` runs every
gate. The checkout holds no install target: the install script and CPAN serve an
operator, and `make dist` builds the packed file under `build/`.

## In a FuguBSD repository

A consumer repository runs the program through the wrapper shim
`scripts/fugubench`. The org pack of FuguBSD/Tooling syncs that shim, and the
shim pins one release. It downloads the packed file one time, holds it to a
digest, and keeps it under `~/.cache/fugubench/<version>/`. A new release
reaches the repository through a sync of the org pack.

`FUGUBENCH` names another program in the environment, and the shim runs that
file in place of the release. A developer points it at `bin/fugubench` of a
checkout.

## Verify

```sh
fugubench version
fugubench --help
```
