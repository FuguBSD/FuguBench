# Worktrees

`fugubench worktree` makes, removes, and lists the worktrees of a checkout, and
it clones the gitignored trees of the main checkout into a worktree. The design
comes from Workspace WS-WORKTREE and Workspace WS-BOOTSTRAP.

<a id="wt-create"></a>

## Create

- **WT-CREATE-1** — `worktree create <name>` must make the worktree at
  `<root>/<worktree.base>/<name>`, on a new branch `<name>` that starts at the
  local HEAD of the main checkout.
- **WT-CREATE-2** — A name must hold letters, digits, a dot, a dash, an
  underscore, and a slash, and no `..` segment. The first character must be a
  letter or a digit. A name that starts with a dash reaches git as an option.
  The verb must refuse a name whose worktree would sit inside an existing
  worktree. The removal of the outer worktree destroys the inner one. Two
  worktrees under one plain parent directory are permitted.
- **WT-CREATE-3** — The verb must make the branch first, as its own step, with
  `git branch`. That step is the lock against a parallel create of one name: one
  create is successful, and the others stop and change nothing.
- **WT-CREATE-4** — After the worktree exists, the verb must run
  `make -C <worktree> bootstrap MAIN=<root>` when the worktree holds a makefile.
  The bootstrap belongs to the repository, and the make target names the paths
  to clone.
- **WT-CREATE-5** — The verb must write the worktree path to standard output as
  the only line. This is the contract of the WorktreeCreate hook
  (HOOK-WORKTREE-1).
- **WT-CREATE-6** — After a failure, or after SIGINT or SIGTERM, the verb must
  stop its child process group and wait for it. It must then remove all that it
  made: the worktree directory, the branch, and each empty parent directory. A
  failed create leaves no worktree and no branch.
- **WT-CREATE-7** — A second `create` of a name whose worktree exists must run
  the bootstrap again, write the path again, and exit 0. A caller can run the
  same create twice, and the second run must not fail (HOOK-WORKTREE-3). A path
  that exists, but that is no worktree of that name, stays an error. The message
  must name the remove command as the remedy.

<a id="wt-remove"></a>

## Remove

- **WT-REMOVE-1** — `worktree remove [--force] <name>` must remove the worktree
  and delete its branch. Only an operator runs it, and no hook calls it (D-06).
- **WT-REMOVE-2** — Without `--force`, the verb must refuse a worktree that
  holds work at risk, and the message must name each cause. The causes are an
  uncommitted change in the worktree or in a repository inside it, and a commit
  that no remote holds. `--force` overrides the refusal.
- **WT-REMOVE-3** — The walk for the repositories inside a worktree must stop at
  each repository that it finds. It must skip `scratch/` and a nested worktree
  directory, which is the `worktree.base` directory of the checkout. In a
  repository with no remote, a commit that the `main` branch holds is safe. A
  linked worktree shares its ref store with the main checkout, so its count
  reads its own HEAD alone.
- **WT-REMOVE-4** — The verb must remove a locked worktree, debris from a killed
  create, and a worktree that a user deleted by hand. A second run causes no
  change. git knows no debris, and its discovery walks up from the debris to the
  checkout above it. So the verb must trust no answer of git about a directory
  that git does not know.
- **WT-REMOVE-5** — The verb must never delete the branch `main`, and never the
  branch that the main checkout has checked out.
- **WT-REMOVE-6** — The verb must resolve symbolic links, and it must refuse a
  path that resolves outside the worktree base. A parallel remove that removes
  the directory first is not an error.
- **WT-REMOVE-7** — After the removal, the verb must remove each empty parent
  directory up to the base.

<a id="wt-list"></a>

## List

- **WT-LIST-1** — `worktree list` must report each worktree with its name, its
  age in days, and its state. The line must be `%-40s %4s d  %s`: the name, the
  age, and the state. The state is `clean`, or each cause of WT-REMOVE-2. The
  age comes from the `.git` file of the worktree, which records the creation and
  which later work leaves alone. A `.git` file that no read reaches gives the
  age `?`.
- **WT-LIST-2** — Without a worktree, the verb must print `no worktrees`.

<a id="wt-clone"></a>

## Clone

- **WT-CLONE-1** — `worktree clone <path>...` must copy gitignored paths from
  the main checkout that `-C` names into the current directory, with no network
  and no `gh`.
- **WT-CLONE-2** — For a path that is a git repository, the verb must make a
  local clone. It must set the `origin` of the clone to the origin URL of the
  source. For a directory of repositories, it must clone each child. For a plain
  file, it must copy the file.
- **WT-CLONE-3** — The verb must copy each regular `.env` file of a cloned tree,
  at any depth, with the mode of the source. It must skip `.git` and a nested
  worktree directory (WT-REMOVE-3), and it must not copy through a symbolic
  link.
- **WT-CLONE-4** — A destination that exists must stay as it is, so a second run
  repairs a partial bootstrap and keeps local changes. The verb replaces a
  symbolic link at the destination of a file copy with a regular file.
- **WT-CLONE-5** — A path must be relative, with no `..` segment, and not `.`.
  The first character must be a letter, a digit, a dot, or an underscore. A
  gitignored path starts with a dot, and a path that starts with a dash reaches
  git as an option. The verb skips a path that is absent in the main checkout,
  with a message.
- **WT-CLONE-6** — The verb must write inside the current directory only. In the
  main checkout itself, it must report that fact and change nothing.
- **WT-CLONE-7** — The verb must write no credential into a settings file. A
  `.env` file is a file copy, and the HOME profiles hold the credentials
  (Workspace WS-PROFILES).

<a id="wt-safety"></a>

## Safety under parallel runs

- **WT-SAFETY-1** — Create and remove must confine their changes to the worktree
  base, and clone to the current directory.
- **WT-SAFETY-2** — After SIGKILL during a bootstrap, debris stays. The debris
  is a branch without a directory, a directory that git does not know, and an
  orphan child in the worktree. Remove must handle each one.
- **WT-SAFETY-3** — Every child of create must run in its own process group, so
  a signal handler stops the whole tree before the cleanup starts.
