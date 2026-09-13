# The Claude Code hooks

`fugubench hook <event>` answers one hook event of Claude Code. The harness
writes a JSON payload to standard input, and the program reads it (D-07). The
design of the events comes from Workspace WS-HOOKS and Workspace LIB-HOOKS.

<a id="hook-events"></a>

## Events

- **HOOK-EVENTS-1** — The events are `SessionStart`, `SessionEnd`,
  `WorktreeCreate`, and `WorktreeRemove`. Another word is a usage error.
- **HOOK-EVENTS-2** — The verb must read the payload as JSON from standard
  input. A payload that does not parse is a warning, and the verb exits zero.
- **HOOK-EVENTS-3** — The session events must never stop a session: every
  failure warns and exits zero. `WorktreeCreate` must fail when the worktree
  cannot be made, because the harness needs the path. `WorktreeRemove` must exit
  zero always.
- **HOOK-EVENTS-4** — The verb must exit at once, with no change, when the
  payload holds `agent_id`. That payload is a sub-agent, and an observer
  dispatches many.
- **HOOK-EVENTS-5** — The checkout root comes from the payload `cwd`, through
  the walk of CLI-CHECKOUT. A session can start in a worktree, and a worktree is
  a checkout with its own library clone.

<a id="hook-session"></a>

## The session events

- **HOOK-SESSION-1** — `SessionStart` must run `wiki init` and then `wiki open`.
  The session identifier is `session_id` of the payload. The verb replaces each
  character outside letters, digits, a dot, a dash, and an underscore with a
  dash.
- **HOOK-SESSION-2** — The project of the session is the child of
  `wiki.projects` that holds `cwd`, and otherwise `wiki.project`.
- **HOOK-SESSION-3** — `SessionEnd` must run `wiki close`. `SessionEnd` does not
  fire on an abnormal stop, so every observation reaches a commit through
  `wiki note` at capture time. `close` adds no durability of its own.
- **HOOK-SESSION-4** — `SessionStart` fires for every session, and most sessions
  run no campaign. `open` must stay cheap: one fetch, one commit, and one push.

<a id="hook-worktree"></a>

## The worktree events

- **HOOK-WORKTREE-1** — `WorktreeCreate` must read `cwd` and `name` from the
  payload, and run `worktree create` with `cwd` as the root. It must write the
  worktree path to standard output as the only line.
- **HOOK-WORKTREE-2** — `WorktreeRemove` must remove nothing (D-06). It must
  read `worktree_path`, print the path and the manual command
  `make -C <root> worktree-remove NAME=<name>` to standard error, and exit zero.
- **HOOK-WORKTREE-3** — Claude Code runs the create hook again when a session
  reconnects, with the same name. `WorktreeCreate` must exit 0 for that run, and
  WT-CREATE-7 gives the result.

<a id="hook-install"></a>

## Installation

- **HOOK-INSTALL-1** — `hook install` must write the four hook entries into
  `.claude/settings.json` of the checkout, and it must keep every other key of
  the file. A second run causes no change.
- **HOOK-INSTALL-2** — Each entry must run the shim of the checkout,
  `"$CLAUDE_PROJECT_DIR/scripts/fugubench" hook <event>`, and nothing else. No
  entry needs `jq`.
- **HOOK-INSTALL-3** — Each entry must carry an explicit timeout: 120 seconds
  for `WorktreeCreate`, 60 for `WorktreeRemove`, 60 for `SessionStart`, and 30
  for `SessionEnd`. Without one, the `SessionEnd` hooks share a budget of 1.5
  seconds, and a commit with a push does not fit it.
- **HOOK-INSTALL-4** — `hook install` must set `worktree.baseRef` to `head`,
  because a worktree starts at the local HEAD. Without the hooks, the built-in
  creation branches from `origin/main` and skips the bootstrap.
