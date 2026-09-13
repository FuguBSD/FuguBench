# The learning library

`fugubench wiki` operates the learning library: a git repository of flat pages,
cloned below the home of `wiki.origin`. The design comes from Workspace
LIB-WIKI, Workspace LIB-PAGES, and Workspace LIB-CANDIDATE. Every capture
commits, and then pushes. The commit carries the durability, and the push
carries the visibility.

<a id="wiki-clone"></a>

## The clone

- **WIKI-CLONE-1** — `wiki init` must clone `wiki.origin` into
  `<home of wiki.origin>/<wiki.dir>` when the directory is absent. A second run
  causes no change.
- **WIKI-CLONE-2** — A failed clone must warn and exit zero. The repository can
  be absent, and a checkout without network access is normal, so the session
  that follows must still start.
- **WIKI-CLONE-3** — A verb that needs the clone must report its absence and
  exit zero, except `init`. A verb other than `init` must treat an absent
  `wiki.origin` as an absent clone. No hook must stop a session because the
  library is absent.

<a id="wiki-pages"></a>

## Pages

- **WIKI-PAGES-1** — Pages must stay flat. A page name must hold letters,
  digits, a dot, a dash, and an underscore, with a leading letter and no `..`.
  The verb must accept the name with or without the `.md` suffix.
- **WIKI-PAGES-2** — A page name must not start with `SCRATCHPAD`, because the
  prose lint skips that prefix.
- **WIKI-PAGES-3** — A session page is `Session-<project>-<date>-<n>.md`. Its
  header holds the title, a `Session:` line with the session identifier, a
  `Project:` line, an `Opened:` line in UTC, and the heading `## Observations`.
  The title is `# Session <project> <date> <n>`, so it carries the index of the
  name. A rename of the page must write the title again. `close` appends a
  `Closed:` line.
- **WIKI-PAGES-4** — The session identifier lives in the page and never in the
  name, so `open` stays idempotent across a resume and a compact. One session
  can drive several runs, so no run identifier reaches a name.

<a id="wiki-open"></a>

## Open

- **WIKI-OPEN-1** — `wiki open <project> <session>` must start the session page,
  commit, and push. When a page holds the session identifier already, the verb
  must print that page and change nothing.
- **WIKI-OPEN-2** — The verb must fetch the origin before it reads the pages of
  the clone. It must fast-forward a local branch that holds no commit of its
  own. It must count the pages of the day in the local clone and in the fetched
  branch together. It must find the page of the session in the working tree, or
  in the fetched branch. A clone with a commit of its own takes no fast-forward,
  and its working tree can hide that page. A stale clone alone gave two sessions
  one name, and it hid the page of a session that resumes.
- **WIKI-OPEN-3** — A push can fail because the origin holds a page of the same
  name. The verb must then rename its page to the next free `<n>`, amend the
  commit, and retry (D-08). It must not rebase an add/add conflict, and it must
  leave no stopped rebase behind. A failed rename must end the retries, and the
  verb must exit non-zero. A failure after the rename leaves the file and the
  commit apart.
- **WIKI-OPEN-4** — The verb must print the final page name to standard output
  as the only line.
- **WIKI-OPEN-5** — A project token and a session token must hold letters,
  digits, a dot, a dash, and an underscore only. The first character must be a
  letter or a digit. A token that starts with a dash reaches git as an option.

<a id="wiki-capture"></a>

## Capture

- **WIKI-CAPTURE-1** — `wiki note <page> <file>` and `wiki admit <page> <file>`
  must append the text of the file to the page after one blank line, commit, and
  push. The two verbs differ in the commit subject only. An empty file is an
  error.
- **WIKI-CAPTURE-2** — `wiki close <session>` must append the `Closed:` line to
  the page of the session, commit, and push. A second close changes nothing, and
  a session with no page is normal.
- **WIKI-CAPTURE-3** — Every commit of the verb must carry a change. A
  subcommand with nothing to add must stop before it stages, because a commit of
  nothing fails.
- **WIKI-CAPTURE-4** — A failed push must not stop a capture. The verb must warn
  and exit zero, and the commit stays for the next push.
- **WIKI-CAPTURE-5** — On a rejected push, the verb must fetch, rebase, and
  retry, three times at most. It must never force a push, because a ruleset of
  the library forbids one. The rename of WIKI-OPEN-3 comes before a rebase.
  After the last rejection the verb must run no fetch, no rename, and no rebase.
- **WIKI-CAPTURE-6** — With a detached HEAD, the verb must warn and push
  nothing.

<a id="wiki-status"></a>

## Status and candidates

- **WIKI-STATUS-1** — `wiki status` must report each open session with its page,
  its `Claim:` count, and its `Admitted:` count, and then the count of unpushed
  commits. A page with no text under `## Observations` is not an open session.
- **WIKI-STATUS-2** — `wiki candidates` must read the page `Rule-candidates.md`
  and report each undelivered candidate with its age in days and its date. A
  candidate is a list item that starts with a date, joined across its
  continuation lines. `Delivered:` marks a candidate done.
- **WIKI-STATUS-3** — `wiki candidates` must exit zero when the clone or the
  page is absent, so a checkout without a library passes `make check`.

<a id="wiki-confine"></a>

## Confinement

- **WIKI-CONFINE-1** — The verb must write inside the library only. A page name
  with a slash, a dot segment, or a leading dot is invalid.
- **WIKI-CONFINE-2** — The verb must run git with the clone as the working
  directory, and it must send every git message to standard error.
