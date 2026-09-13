# The program

`fugubench` is one executable with one verb for each concern. This document
specifies the executable, the verbs, the discovery of the checkout, and the
configuration keys. It also specifies the Fugu modules that the program uses,
the sandbox, the doctor, and the conformance tests.

<a id="cli-program"></a>

## The executable

- **CLI-PROGRAM-1** — The program must be one file, `fugubench`, that runs with
  perl 5.34 and core modules alone. It must load no CPAN module, and it must
  need no installed Fugu.
- **CLI-PROGRAM-2** — The command line is
  `fugubench [-C <dir>] [--verbose] <verb> [options] [arguments]`. The `-C`
  option names the directory that a verb reads as its checkout root, before the
  discovery of CLI-CHECKOUT. CLI-PROGRAM-7 states the `--verbose` option.
- **CLI-PROGRAM-3** — `fugubench --help` and `fugubench <verb> --help` must
  print the usage to standard output and exit 0. A usage error must print the
  usage to standard error and exit 2. A command line that holds no verb and no
  request for the help is a usage error. A global option in front of no verb
  does not change that.
- **CLI-PROGRAM-4** — Standard output must carry the result of a verb only.
  Every diagnostic, and every line that a child command writes, must go to
  standard error. A hook reads standard output, so a git message must never
  reach it.
- **CLI-PROGRAM-5** — The exit codes come from Fugu LIB-CLI. The codes are 0 for
  success, 1 for a failure, 2 for a usage error, and 3 for a configuration
  error. A verb must not define another code.
- **CLI-PROGRAM-6** — The program must run every command as an argument list,
  and never through a shell. A name that reaches a command must pass a shape
  check first.
- **CLI-PROGRAM-7** — The program must be silent on success, except for the
  result line that a verb defines. A `--verbose` option adds the trace of each
  command to standard error. A verb can add its own progress lines to that
  stream, and DEPS-MANIFEST-9 names the lines of `deps`.

<a id="cli-verbs"></a>

## The verbs

| Verb       | Action                                                     | Document                   |
| ---------- | ---------------------------------------------------------- | -------------------------- |
| `deps`     | Install one dependency environment, or refresh the digests | [deps.md](deps.md)         |
| `fetch`    | Download one URL to one file                               | [deps.md](deps.md)         |
| `worktree` | Create, remove, list, or clone into a worktree             | [worktree.md](worktree.md) |
| `wiki`     | Operate the learning library                               | [wiki.md](wiki.md)         |
| `hook`     | Answer one Claude Code hook event                          | [hooks.md](hooks.md)       |
| `traces`   | Measure the sessions of the checkout                       | [traces.md](traces.md)     |
| `shim`     | Print the wrapper shim of a consumer                       | [dist.md](dist.md)         |
| `install`  | Copy the program into `~/.local/bin`                       | [dist.md](dist.md)         |
| `update`   | Replace the program with a verified release                | [dist.md](dist.md)         |
| `doctor`   | Report the state of the checkout and its tools             | this document              |
| `version`  | Print the version                                          | [dist.md](dist.md)         |

- **CLI-VERBS-1** — The verb table above is the whole surface. A new verb needs
  a unit in the document of its concern.
- **CLI-VERBS-2** — A verb with subcommands takes them as the next word:
  `worktree create`, `wiki note`, and `hook SessionStart`.
- **CLI-VERBS-3** — Each verb must read its options through the dispatcher of
  Fugu LIB-CLI, so no verb repeats the option parsing.

<a id="cli-checkout"></a>

## The checkout

A verb operates one checkout: the repository that holds the manifests, the
worktrees, or the library clone.

- **CLI-CHECKOUT-1** — With `-C <dir>`, the checkout root starts at that
  directory. Without it, the root starts at the payload `cwd` of a hook, or at
  the current directory.
- **CLI-CHECKOUT-2** — The program must walk up from the start to the nearest
  directory that holds `.toolingrc`. A verb that needs a configuration key must
  continue to the nearest `.toolingrc` that holds the key. A clone under
  `Projects/` holds its own `.toolingrc` without a `wiki.origin` key, so the
  walk for the library reaches the workspace.
- **CLI-CHECKOUT-3** — The walk must stop at the filesystem root. When no
  `.toolingrc` exists, the program must report the start directory and exit with
  a configuration error. A sandbox row can run the walk in front of the verb,
  and the report must wait for the verb. A verb that rejects its argument list
  must not report a configuration error.
- **CLI-CHECKOUT-4** — A worktree holds its own `.toolingrc`, so a worktree is a
  checkout of its own. The program must not cut a path at a `.claude/worktrees/`
  marker to find a checkout, except where TRACE-NAME says so.
- **CLI-CHECKOUT-5** — `deps` is the exception. It reads `deps/<OS>.txt`
  relative to the start directory, with no walk. A guest runs `make deps` out of
  an extracted tarball, and that tree holds no `.toolingrc`. The verbs
  `version`, `shim`, `install`, `update`, and `fetch` read no checkout, so the
  walk must not run for them. The install of DIST-INSTALL-3 then works in a home
  with no `.toolingrc`.

<a id="cli-config"></a>

## Configuration

`.toolingrc` is the identity home of the synced tools (Tooling D-02), and the
program reads its keys there. A line holds a key, whitespace, and a value. A `#`
starts a comment.

| Key             | Meaning                                            | Default                        |
| --------------- | -------------------------------------------------- | ------------------------------ |
| `wiki.dir`      | The library clone, under the home of `wiki.origin` | `Wiki`                         |
| `wiki.origin`   | The URL of the library repository                  | none; `wiki init` stops        |
| `wiki.project`  | The project name of a session at the root          | the name of the root directory |
| `wiki.projects` | The directory whose children are project clones    | `Projects`                     |
| `worktree.base` | The directory of the worktrees, under the root     | `.claude/worktrees`            |

- **CLI-CONFIG-1** — The program must read the keys of the table above, and must
  ignore every other key. Other tools own other prefixes.
- **CLI-CONFIG-2** — A key with a default must take the default when the file
  omits it. A key without a default must stop the verb that needs it with a
  configuration error that names the key. The home of a key is the directory of
  the `.toolingrc` that holds it, and the root is the home of a default. A verb
  must anchor a `wiki.` value at the home of `wiki.origin`, and `worktree.base`
  at the root.
- **CLI-CONFIG-3** — A value must pass the shape check of its use. A directory
  is a relative path with no `..` segment, and a URL holds a scheme. The
  `worktree.base` value must name a directory below the root, so a value of `.`
  is an error. A base that is the root itself holds every path of the checkout,
  and the containment guard of `worktree remove` then admits each one. The
  `wiki.dir` value must name a directory below the home of `wiki.origin`, so a
  value of `.` is an error. That value makes the checkout itself the library.
  `wiki open` then writes a session page into the checkout, and it pushes the
  page to the origin of the checkout.

<a id="cli-fugu"></a>

## The Fugu modules

- **CLI-FUGU-1** — The program must use the Fugu modules for the shared
  plumbing. Fugu LIB-CLI holds the dispatch, Fugu LIB-PROCESS runs every child
  command, Fugu LIB-FILE handles the files, and Fugu LIB-LOG writes the
  diagnostics. Fugu LIB-SIGNIFY with the engine of Fugu LIB-ED25519 verifies
  every signature. Fugu LIB-CURL runs every download, and Fugu LIB-SANDBOX holds
  the sandbox.
- **CLI-FUGU-2** — The program must not load a Fugu module outside that set
  without a rule that names it. The pack carries each module that the program
  uses (DIST-PACK), so each one costs bytes in every consumer.
- **CLI-FUGU-3** — The program must not load an `App::` module of another
  distribution. It must not hold a copy of a Fugu module in its own tree.

<a id="cli-sandbox"></a>

## The sandbox

- **CLI-SANDBOX-1** — On OpenBSD, each verb must pledge its promises and unveil
  its paths through Fugu LIB-SANDBOX before it does its work. On another
  platform the calls change nothing.
- **CLI-SANDBOX-2** — A verb that runs a child command must pledge its promises,
  and must unveil nothing. unveil(2) holds across an exec, and no row can name
  each file that a child opens. A verb that opens a file of its own must unveil
  the paths of its row. A row names the checkout root, the install directory of
  DEPS-INSTALL-6, and the cache directory of DIST-SHIM. A row also names one
  temporary directory, the perl library directories, the directory of the
  running file, and the trace root. It must unveil nothing else. The three verbs
  that unveil are `shim`, `install`, and `traces`. Every other verb unveils
  nothing, `deps` among them. The verbs `wiki`, `hook`, `deps`, `fetch`, and
  `update` add a network promise.
- **CLI-SANDBOX-3** — A verb that opens no file must pledge `stdio` and must
  unveil nothing. `stdio` denies open(2), so an unveil under it opens no file
  and hides no file. `version` is that verb.
- **CLI-SANDBOX-4** — A row can give one promise set to a named subcommand. The
  verb must pledge that set for that subcommand. It must pledge the promises of
  the row for every other subcommand. The `list` subcommand of `worktree` writes
  no file, so its set drops the write promises.

<a id="cli-doctor"></a>

## The doctor

- **CLI-DOCTOR-1** — `fugubench doctor` must report the state of the checkout.
  The report holds the version of the program, and the presence of `git`,
  `make`, and a downloader on `PATH`. It holds the hook entries and the worktree
  base reference of `.claude/settings.json`, and the state of the library clone.
- **CLI-DOCTOR-2** — The report must name a library clone that sits in a stopped
  rebase, with the page that the pending commit adds. `doctor --fix` must skip
  the pending commit when it adds a session page with no observation, and must
  refuse otherwise. The `Closed:` line of `wiki close` is no observation. A
  rebase that stops again after the skip must give a problem line that names the
  skip and the new stop.
- **CLI-DOCTOR-3** — `doctor` must exit non-zero when a report line names a
  problem, so a make target can gate on it.

<a id="cli-conformance"></a>

## Conformance

The program replaces four scripts that have tests, and the tests come with it.

- **CLI-CONFORMANCE-1** — The test suite must hold the black-box tests of the
  Workspace scripts `worktree.pl`, `wiki.pl`, and `traces.pl`. A ported test
  must keep each assertion of the source. It must change the invocation, the
  fixture, the pragma block of the source floor, and the unit citations. It must
  change nothing else. An assertion on a file of the Workspace stays in the
  Workspace test. A behavior that a test asserts must hold in the program.
- **CLI-CONFORMANCE-2** — The dry-run trace of `deps` over the manifests of
  every consumer must equal the trace of the synced `scripts/deps`, line for
  line. The rule holds until Tooling retires the script. The fixtures are copies
  of the consumer manifests and digest files under `t/`. The verb downloads
  in-process, so the test must replace the path of the `ftp` helper with
  `fugubench fetch`, and each temporary directory with one token. It must
  compare the `+ ` lines, and it must change nothing else.
