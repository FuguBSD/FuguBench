# Dependencies

`fugubench deps` installs the external tools, the Perl distributions, the CPAN
modules, and the prebuilt binaries that a repository names in `deps/<OS>.txt`.
The design comes from the synced `scripts/deps` of Tooling, and the verb must
give the same trace over the same manifests (CLI-CONFORMANCE-2). Two parts
change. Every download goes through Fugu LIB-CURL, and every signature check
runs in-process through Fugu LIB-SIGNIFY with the engine of Fugu LIB-ED25519.

<a id="deps-manifest"></a>

## The manifest

- **DEPS-MANIFEST-1** — The verb must read `deps/<OS>.txt` relative to the start
  directory, where `<OS>` is the system name of `uname`. The `--os` and `--arch`
  options replace the two words of `uname`. The verb reads no path relative to
  the program, because a guest runs it out of an extracted tarball.
- **DEPS-MANIFEST-2** — A line holds an environment, a type, and a name, with
  whitespace between them. The environments are `tool`, `runtime`, `test`, and
  `develop`. The types are `pkg`, `dist`, `cpan`, and `bin`. A `#` at the start
  of the first word starts a comment.
- **DEPS-MANIFEST-3** — The verb must validate every line before the first
  install, and not the lines of the wanted environment alone. An unknown
  environment, an unknown type, and a line with fewer than three words are each
  an error that names the line.
- **DEPS-MANIFEST-4** — `deps <environment>` must install the entries of that
  environment in the order `pkg`, `dist`, `cpan`, `bin`. A package can give the
  toolchain that a dist build needs, and a dist can give a module that the cpan
  list builds on. A binary depends on nothing here.
- **DEPS-MANIFEST-5** — Without a manifest for the operating system, the verb
  must report that fact and exit zero.
- **DEPS-MANIFEST-6** — `--dry-run` must print each command that the verb would
  run, and it must run none of them. Each line starts with `+ ` and holds every
  argument shell-quoted. The trace is the result of a dry run, so it goes to
  standard output. A run without `--dry-run` must write no trace there, and
  `--verbose` must trace each command on standard error. The trace is the oracle
  of CLI-CONFORMANCE-2.
- **DEPS-MANIFEST-7** — A `pkg` name and a `cpan` name must not start with a
  dash, and neither may be a URL. Both reach a package manager, which owns its
  own check. A `dist` URL and a `bin` URL must take the shape check of
  DEPS-FETCH-4, because each one reaches the downloader.
- **DEPS-MANIFEST-8** — A `dist` name is one URL. A `bin` name holds the command
  name, the URL, and, for an archive, the path of the file in the archive. An
  archive URL ends in `.tar.gz`, `.tgz`, or `.zip`, and it needs the path. A
  plain URL takes none.

<a id="deps-install"></a>

## The installers

- **DEPS-INSTALL-1** — A `pkg` entry must reach the package manager of the
  platform. The manager is `pkg_add` on OpenBSD, `apt-get install -y` under
  `sudo` on Linux, and `brew install` on Darwin. On Linux an `apt-get update`
  runs first. The verb must give every package of the environment in one
  command.
- **DEPS-INSTALL-2** — A `cpan` entry and a `dist` entry must install through
  `cpanm --notest`. With `PERL_LOCAL_LIB_ROOT` in the environment, the verb must
  add `--local-lib` with that value.
- **DEPS-INSTALL-3** — The verb must use the `cpanm` on `PATH` when one exists.
  Otherwise it must download the standalone `cpanm` script into a temporary
  directory and run it with the current perl. It must not install
  `App::cpanminus`, because that install lands in a user library that `PATH`
  does not hold.
- **DEPS-INSTALL-4** — The cpanm download is the one download with no check,
  because no manifest names it. A repository that wants no unchecked download
  names a cpanminus package in its `tool` environment, and the download never
  runs.
- **DEPS-INSTALL-5** — A `dist` entry must fetch its tarball into a temporary
  directory and check it (DEPS-TIER) before `cpanm` reads it.
- **DEPS-INSTALL-6** — A `bin` entry must install into `~/.local/bin`, with
  mode 755. The verb must stop with an error when `HOME` is unset.
- **DEPS-INSTALL-7** — For an archive, the verb must extract the one named file
  in the temporary directory. It uses `tar` for a tar archive and `unzip` for a
  zip archive. It must copy that file alone.
- **DEPS-INSTALL-8** — A command name becomes a file name in the install
  directory. It must hold letters, digits, a dot, a dash, and an underscore
  only. An archive path must hold no empty and no parent segment. It must not
  start with a dash, which `tar` and `unzip` read as an option. The check must
  run over every line, and again after the alias words expand.
- **DEPS-INSTALL-9** — The verb must resolve every entry of a type, and check
  that a tier covers it, before the first install of that type. That pre-pass
  reads the digest file and the key set, and it asks no network. A set with one
  entry that no tier covers must install nothing, and the verb must make no
  install directory. The digest of an entry takes its check at the download of
  that entry, which the install of that entry follows. A mismatch on a later
  entry leaves an earlier one installed. The install order comes from the synced
  `scripts/deps`, which CLI-CONFORMANCE-2 pins.
- **DEPS-INSTALL-10** — On success the verb must end with one line that names
  the installed environment.

<a id="deps-alias"></a>

## The platform aliases

A release asset spells one platform in more than one way. The gitleaks release
names the x86_64 architecture `x64`, and the gh release names Darwin `macOS`. A
manifest must hold neither word.

- **DEPS-ALIAS-1** — A manifest must write `{os}` and `{arch}` in place of a
  platform word. The verb must expand both, in the URL and in the archive path.
- **DEPS-ALIAS-2** — The verb must hold one alias table for each word, in
  preference order. Darwin gives `darwin`, `macOS`, and `osx`. Linux gives
  `linux`, and OpenBSD gives `openbsd`. `x86_64` and `amd64` give `amd64`,
  `x64`, and `x86_64`. `aarch64` and `arm64` give `arm64` and `aarch64`. An
  unknown word gives itself, in lower case for the system name. The table must
  hold no two spellings that one host answers alike.
- **DEPS-ALIAS-3** — The verb must form one candidate URL for each alias pair,
  and take the candidate that `deps/SHA256.txt` records. No match and more than
  one match are each an error that names the repair.
- **DEPS-ALIAS-4** — The resolution must not ask the network.
- **DEPS-ALIAS-5** — An entry with a placeholder needs a recorded digest,
  because the resolution reads the digest file. The signify tier serves an entry
  without a placeholder only.
- **DEPS-ALIAS-6** — Each placeholder of the archive path must also sit in the
  URL. Only the URL selects the platform.

<a id="deps-tier"></a>

## The download check

The two tiers key their digests apart. `deps/SHA256.txt` gathers many upstreams,
so it keys on the download URL. The signed manifest of a release covers one
release directory with unique file names, so it keys on the file name.

- **DEPS-TIER-1** — Each download must land in a temporary directory of its own.
  The verb must check the bytes before it extracts an archive, before `cpanm`
  reads a tarball, and before a file reaches the install directory.
- **DEPS-TIER-2** — A failed check must stop the install at once, and the entry
  of that check must install nothing. An earlier entry of the same set installs
  before the download of a later one, so it stays. DEPS-INSTALL-9 states what
  the pre-pass of a set covers.
- **DEPS-TIER-3** — `deps/SHA256.txt` records a sha256 digest for each download
  with a versioned name. A line reads `SHA256 (url) = hexdigest`, and the key is
  the whole download URL. The verb must read and write the file through the
  manifest reader and writer of Fugu LIB-SIGNIFY.
- **DEPS-TIER-4** — A bad line, a digest that is not 64 hexadecimal characters,
  and a duplicate key are each an error.
- **DEPS-TIER-5** — A key must hold a scheme. A key that is a file name comes
  from an older file. It must stop the install with a message that names
  `deps --update-sums` as the repair.
- **DEPS-TIER-6** — With a recorded digest, the verb must hold the download to
  it.
- **DEPS-TIER-7** — Without a recorded digest, the verb must derive `SHA256` and
  `SHA256.sig` from the directory of the URL and fetch both. It must verify the
  signature before it downloads the file. The manifest keys on the file name,
  and the verb must hold the file to that digest.
- **DEPS-TIER-8** — The signature check must run in-process, through Fugu
  LIB-SIGNIFY with the engine of Fugu LIB-ED25519. No signify(1) is needed on
  the host, so a `tool` entry can take the signify tier, and a manifest needs no
  signify package. Tooling MK-DEPS-4 and Tooling MK-DEPS-5 end for a consumer of
  this verb.
- **DEPS-TIER-9** — An entry with no recorded digest and no signature must stop
  the install. The cpanm download is the one exception (DEPS-INSTALL-4).
- **DEPS-TIER-10** — A digest mismatch must name the repair of its tier. A
  recorded digest names `deps --update-sums --force`. A signed digest names a
  report to the upstream, because the served file disagrees with the release.
- **DEPS-TIER-11** — A message that stops an install must name the command that
  repairs it, when one exists.
- **DEPS-TIER-12** — A download URL must name a file. It must hold no
  parenthesis and no space, which the line format of the digest file reserves.
  The check must run over every line of the manifest and over each candidate of
  the alias expansion.
- **DEPS-TIER-13** — A signature over a stable name binds no version, so a
  server can replay an earlier signed release. A consumer that must not take an
  earlier release names a versioned URL and a recorded digest.

<a id="deps-keys"></a>

## The signify keys

- **DEPS-KEYS-1** — The verb must read `deps/KEYS.txt` and then
  `deps/KEYS.local.txt`. The org pack owns the first file, and a consumer pins a
  third-party key in the second.
- **DEPS-KEYS-2** — A key line holds a name and then one of two forms. Two
  fields give the key body: 56 base64 characters that decode to 42 bytes with
  the prefix `Ed`. Three fields give the URL of a key file and its sha256
  digest, and the digest is the trust anchor.
- **DEPS-KEYS-3** — The line order is the trust order, and the current key comes
  first. Every declared key verifies every signify-tier download, so no key
  binds to one entry.
- **DEPS-KEYS-4** — A key name must hold letters, digits, a dot, a dash, and an
  underscore only, and it must appear one time. A key body must decode, and a
  digest must be 64 hexadecimal characters. A key URL must take the shape check
  of DEPS-FETCH-4, because it reaches the downloader. Each other shape is an
  error that names the line.
- **DEPS-KEYS-5** — An empty key set is valid. The signify tier of an install
  must then stop with an error that names the empty set. The signed-manifest
  probe of `deps --update-sums` must report the same fact as a warning, and the
  refresh must go on. A manifest that no key verifies keeps the entry off the
  digest tier (DEPS-SUMS-6).
- **DEPS-KEYS-6** — A key of the URL form must download into a temporary
  directory on each use. The verb must hold it to the recorded digest. A cached
  copy would carry the check of an earlier entry.
- **DEPS-KEYS-7** — A key that fails its digest, or that no server answers, must
  not stop the trust order. The verb must try the next key, warn about the
  failed one, and report each failure when no key verifies.

<a id="deps-sums"></a>

## The digest refresh

`deps --update-sums [--force]` records the digests. The operator runs it, and
the install path must not.

- **DEPS-SUMS-1** — The command must record the digest of each versioned
  download that the manifest names. It must keep a URL that the file records
  already.
- **DEPS-SUMS-2** — A versioned name carries a digit in the path of its URL. A
  stable name carries none, or it holds `/releases/latest/`. The test reads the
  manifest, and never the network.
- **DEPS-SUMS-3** — The command must skip a stable name without a placeholder. A
  server that withholds its signature must not make the command pin the bytes
  that it serves.
- **DEPS-SUMS-4** — An entry with a placeholder is never a stable name, because
  the resolution reads the digest file. Such an entry needs a recorded digest,
  and a signed manifest beside its URL must supply it.
- **DEPS-SUMS-5** — The command must not record a digest of its own download for
  a URL that a signed manifest sits beside. Such a digest would outrank the
  signature, and the command authenticates no download.
- **DEPS-SUMS-6** — The signed-manifest test must ask each distinct resolved
  directory of the candidates, and never the directory of the template. A
  manifest that answers keeps the entry off the digest tier, whether or not a
  key verifies it.
- **DEPS-SUMS-7** — A verified manifest that names no candidate must not hide a
  later directory that holds the release. An entry that reaches no candidate
  must fail the run.
- **DEPS-SUMS-8** — Each candidate must download into a directory of its own,
  because two candidates can share a file name.
- **DEPS-SUMS-9** — The command must record the first candidate that answers,
  and it must warn about every other one. The install rejects a URL with two
  recorded candidates.
- **DEPS-SUMS-10** — `--force` must rewrite a recorded digest, pin a stable
  name, and override the signed-manifest test with a warning first. It must drop
  every other recorded candidate of the same entry.
- **DEPS-SUMS-11** — The command must drop a file-name key when it records the
  URL that replaces it, and report each drop. A key that this run cannot replace
  must stay, because one run reads one manifest.
- **DEPS-SUMS-12** — A run that records nothing must leave the file as it was,
  and say so. A run with a failed entry must leave the file as it was, and must
  name a next step. The command must report a recorded URL only when it writes
  the file.
- **DEPS-SUMS-13** — `--force` belongs to `--update-sums`, and `--dry-run` does
  not. An install run must reject `--force`, and a refresh must reject
  `--dry-run`.

<a id="deps-fetch"></a>

## The fetch

- **DEPS-FETCH-1** — Every download of the verb must go through Fugu LIB-CURL: a
  release asset, a signed manifest, a key file, and the cpanm script. The
  program ships no shell helper for a download.
- **DEPS-FETCH-2** — `fugubench fetch <file> <url>` must expose the same
  downloader as a verb, with the argument order of the `ftp` helper of Tooling.
  A make recipe that called the helper calls the verb.
- **DEPS-FETCH-3** — A probe for a signed manifest must read a 404 as the normal
  answer, and the verb must write nothing about it. A connection failure is a
  failure of the run.
- **DEPS-FETCH-4** — A URL that reaches the downloader must start with a scheme.
  Fugu LIB-CURL puts the URL last, and it writes no `--` separator. A URL that
  starts with a dash then reaches the downloader as an option. A scheme starts
  with a letter, so one rule covers both shapes. The `fetch` verb and `deps`
  must run one shared check (CLI-PROGRAM-6). A bad URL on the `fetch` command
  line is an invalid argument, and the verb must return 2.
