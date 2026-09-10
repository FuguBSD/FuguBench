# The session yardstick

`fugubench traces` measures the Claude Code sessions of a checkout. The design
comes from Workspace WS-SESSION. Claude Code keeps one trace directory for each
working directory under `~/.claude/projects/`. The name of the directory is the
absolute path of the working directory. The harness replaces each character
outside letters, digits, and a hyphen with a hyphen.

<a id="trace-name"></a>

## The checkout name

- **TRACE-NAME-1** — The verb must derive the trace name from the checkout root
  of CLI-CHECKOUT, cut at the last `.claude/worktrees/` marker. A nested
  checkout holds the marker more than one time, and a cut at the first marker
  names the wrong checkout.
- **TRACE-NAME-2** — The verb must read the trace directory of the checkout, of
  each worktree of it, and of each project clone in either. The match takes the
  exact name forms, so a sibling checkout such as a backup stays out.
- **TRACE-NAME-3** — `--root <dir>` names a trace root in place of
  `~/.claude/projects/`, and `--name <name>` replaces the derived name. The
  tests use both.

<a id="trace-columns"></a>

## The columns

- **TRACE-COLUMNS-1** — The verb must print one line for each session that holds
  a request, sorted by start time, under a header. A session with no request
  gets no line. A name with no trace directory gives one line that says so.
- **TRACE-COLUMNS-2** — The columns are `session`, `start`, `reqs`, `peak`,
  `out`, `panel`, `edits`, `sub-in`, `sub-out`, and `rev-peak`. `session` is the
  first eight characters of the identifier, and `start` is the time of the first
  record, in UTC.
- **TRACE-COLUMNS-3** — `peak` is the largest context of one request: the fresh
  input tokens, the cache writes, and the cache reads. `out` is the output of
  the main session, thinking included.

<a id="trace-usage"></a>

## Usage

- **TRACE-USAGE-1** — One request writes one record for each content block, and
  each record carries the usage of the whole request. An early record can carry
  a partial count, so the verb must take the usage of the last record of a
  request. A record with no request identifier counts alone.
- **TRACE-USAGE-2** — The verb must parse an assistant record only, and it must
  read the start time from the first record that carries one. A full parse of
  every record costs minutes over a long history.

<a id="trace-panel"></a>

## The panel

- **TRACE-PANEL-1** — A panel launch is a `tool_use` block of the `Agent` or
  `Task` tool whose `subagent_type` is `reviewer`. A catch-all type,
  `general-purpose` or `claude`, and an absent type name no role, so the
  description decides: it holds the word `panel`. Another type is no launch.
- **TRACE-PANEL-2** — `panel` counts the requests that hold a panel launch.
- **TRACE-PANEL-3** — `edits` counts the `Edit`, `Write`, `MultiEdit`, and
  `NotebookEdit` blocks of the main session after the first panel launch. A
  block counts when its target is a repository file. An absolute target must sit
  inside the checkout on a directory boundary. A relative target sits inside it.
  A target under `scratch/` or a `SCRATCHPAD*.md` file is no repository file. A
  block with no target counts.

<a id="trace-sub"></a>

## The sub-agents

- **TRACE-SUB-1** — `sub-in` and `sub-out` sum the input and the output of every
  sub-agent trace of the session. The traces sit under `<session>/subagents/`
  and under each workflow directory below it.
- **TRACE-SUB-2** — `rev-peak` is the largest peak of one panel reviewer. Each
  sub-agent trace has a sibling `.meta.json` with the `toolUseId` of its launch.
  The verb maps the panel launches to their traces through it.
