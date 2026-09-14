# Install FuguBench

FuguBench runs on core Perl v5.34 or later. One packed Perl file holds every
verb, and it carries the Fugu modules that it uses, so it loads no CPAN module.
Two flows install the program: the install script, and CPAN with cpanm. Two
flows run it in place: `bin/fugubench` of a checkout, and the wrapper shim of a
FuguBSD repository.

## With the install script

```sh
curl -fsSL https://bench.fugubsd.org/get | sh
```

That address serves a stub, and the stub runs the install script of the latest
release. The script downloads the packed file, holds it to its sha256 digest,
and copies the program to `~/.local/bin/fugubench`. It prints a hint when `PATH`
does not hold that directory.

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
make deps-test
```

`make deps` installs the latest
[Fugu release](https://github.com/FuguBSD/Fugu/releases/latest), and
`make deps-test` adds the Perl::Critic and the Perl::Tidy of the lint and the
format gates. The checkout then runs `bin/fugubench`, and `make check` runs
every gate. The Markdown format gate runs prettier through `bunx`, so `bun` must
sit on `PATH`.

On Darwin and on Linux, `make deps` also installs `signify` and `gitleaks`.
OpenBSD base holds signify(1), and gitleaks publishes no OpenBSD build. An
operator on OpenBSD installs gitleaks by hand, or the gitleaks gate of
`make check` fails.

The checkout holds no install target: the install script and CPAN serve an
operator, and `make dist` builds the packed file under `build/`.

## In a FuguBSD repository

No FuguBSD repository holds a shim today. A later plan of FuguBSD/Tooling adds
the wrapper shim `scripts/fugubench` to the org pack, and a sync then delivers
it to each consumer.

The shim pins one release. It downloads the packed file one time, holds it to a
digest, and keeps it under `~/.cache/fugubench/<version>/`. A sync of the org
pack carries each new release. `fugubench shim` prints the shim of the release
that runs the verb. A build that no release stamped carries no version, so the
verb refuses there.

`FUGUBENCH` names another program in the environment, and the shim runs that
file in place of the release. A developer points it at `bin/fugubench` of a
checkout.

## Verify

```sh
fugubench version
fugubench --help
```
