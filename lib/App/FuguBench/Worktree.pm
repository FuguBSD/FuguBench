# ex:ts=8 sw=4:
# $OpenBSD$
#
# Copyright (c) 2026 Dick Olsson <hi@senzilla.io>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

package App::FuguBench::Worktree;

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Cwd            ();
use File::Basename qw(dirname);
use File::Find     ();
use File::Path     ();
use File::Spec     ();

use Fugu::CLI qw(EXIT_SUCCESS EXIT_ERROR);
use Fugu::Process;

# App::FuguBench::Worktree - the worktree verb.
#
# The verb makes, removes, and lists the worktrees of one checkout,
# and it clones the gitignored trees of that checkout into a
# worktree. This change holds the subcommands create and list. An
# unknown subcommand gives the usage error.
#
# The root of the verb is the main checkout, and -C names it. A
# linked worktree holds a .git file, not a directory, so the verb
# refuses such a root. No worktree then nests under another one.
#
# Create makes the branch first, as its own step. That step is the
# lock against a parallel create of one name. After that step the
# verb owns all that it makes, so a failure and a signal both run
# one cleanup.
#
# A second create of a name whose worktree exists runs the bootstrap
# again and writes the path again. Claude Code runs the create hook
# again when a session reconnects, and that run must not fail.

# The subcommands of this change. An unknown word gives the usage
# error, and a subcommand of a later change is an unknown word.
my %SUBCOMMAND = (
	create => \&_create,
	list   => \&_list,
);

# The shape of a worktree name (WT-CREATE-2). The first character is
# a letter or a digit: a name that starts with a dash reaches git as
# an option.
my $NAME = qr{\A[A-Za-z0-9][A-Za-z0-9._/-]*\z};

# The format of one line of the listing (WT-LIST-1): the name, the
# age in days, and the state.
use constant LINE => '%-40s %4s d  %s';

# The makefiles that make reads, in the order of make itself.
use constant MAKEFILES => qw(GNUmakefile Makefile makefile);

# App::FuguBench::Worktree->command($verb):
#	The entry of the Fugu::CLI table. The module holds one verb,
#	so it ignores the name.
sub command ( $, $ )
{
	return {
		summary => 'create or list a worktree of the checkout',
		usage   => 'create <name> | list',
		run     => sub ( $app, @argv ) { return _run( $app, @argv ) },
	};
}

# _run($app, @argv):
#	The body of the verb. It reads the subcommand as its first
#	argument. Each subcommand counts its own arguments before it
#	looks for the root, so a usage error comes before a
#	configuration error.
sub _run ( $app, @argv )
{
	my $word = shift @argv;
	my $sub  = defined $word ? $SUBCOMMAND{$word} : undef;
	return $app->cli->command_usage_error('worktree') unless $sub;

	return $sub->( $app, @argv );
}

# _setup($app):
#	The exit code, the main checkout, and the worktree base, in
#	that order. The code is EXIT_SUCCESS when the other two hold
#	a value, and the method reports every failure itself.
#
#	The path of the root comes from abs_path, because git reports
#	the resolved path of a worktree. The two must agree, or the
#	listing finds no worktree of the base.
#
#	The base is the worktree.base key, and it resolves against the
#	root (CLI-CONFIG-2). A clone under Projects/ can inherit the
#	key from the workspace, and its worktrees belong to the clone.
sub _setup ($app)
{
	my $checkout = $app->checkout
	    or return Fugu::CLI::EXIT_CONFIG_ERROR();
	my $log  = $app->cli->log;
	my $root = Cwd::abs_path( $checkout->root );

	# A linked worktree holds a .git file, and the main checkout
	# holds a .git directory.
	unless ( defined $root && -d "$root/.git" ) {
		$log->error( 'not the main checkout: %s', $checkout->root );
		return EXIT_ERROR;
	}

	my ($value) = $checkout->config('worktree.base');
	my $dir = $checkout->dir_value($value);
	unless ( defined $dir ) {
		$log->error( 'worktree.base: %s', $checkout->error );
		return Fugu::CLI::EXIT_CONFIG_ERROR();
	}

	return ( EXIT_SUCCESS, $root, File::Spec->catdir( $root, $dir ) );
}

# _create($app, @argv):
#	Make one worktree of the checkout, and write its path to
#	standard output as the only line (WT-CREATE-5).
#
#	The branch step comes first, and the cleanup starts after it.
#	A failure and a signal then remove all that the verb made: the
#	worktree, the branch, and each empty parent directory.
#
#	A name whose worktree exists goes to _again, which repeats the
#	bootstrap and the path line (WT-CREATE-7).
sub _create ( $app, @argv )
{
	return $app->cli->command_usage_error('worktree') if @argv != 1;
	my ($name) = @argv;

	my ( $code, $root, $base ) = _setup($app);
	return $code if $code != EXIT_SUCCESS;

	my $log = $app->cli->log;
	unless ( $name =~ $NAME && $name !~ m{[.][.]} ) {
		$log->error( 'invalid worktree name: %s', $name );
		return EXIT_ERROR;
	}

	my $wt = File::Spec->catdir( $base, $name );
	return _again( $app, $root, $name, $wt ) if -e $wt;
	return EXIT_ERROR unless _outside( $app, $base, $name, $wt );

	# The branch step is the lock against a parallel create of one
	# name: one create is successful, and the others stop here and
	# change nothing (WT-CREATE-3).
	unless (
		defined $app->command(
			[ 'git', '-C', $root, 'branch', $name ],
			group => 1
		) )
	{
		$log->error( 'cannot make the branch %s: %s',
			$name, $app->error );
		return EXIT_ERROR;
	}

	my $cleanup = sub { _cleanup( $app, $root, $base, $name, $wt ) };
	my $signal  = sub {
		$SIG{INT} = $SIG{TERM} = 'IGNORE';
		$log->error('interrupted, cleaning up');
		Fugu::Process->terminate( $app->child, group => 1 )
		    if defined $app->child;
		$cleanup->();
		exit EXIT_ERROR;
	};
	local $SIG{INT}  = $signal;
	local $SIG{TERM} = $signal;

	unless (
		defined $app->command(
			[ 'git', '-C', $root, 'worktree', 'add', $wt, $name ],
			group => 1
		) )
	{
		$log->error( 'cannot add the worktree %s: %s',
			$wt, $app->error );
		$cleanup->();
		return EXIT_ERROR;
	}

	unless ( _bootstrap( $app, $root, $wt ) ) {
		$log->error( 'the bootstrap of %s failed: %s',
			$wt, $app->error );
		$cleanup->();
		return EXIT_ERROR;
	}

	say $wt;

	return EXIT_SUCCESS;
}

# _again($app, $root, $name, $wt):
#	The result of a second create of one name (WT-CREATE-7). A
#	session that reconnects runs the create hook again with the
#	same name, and that run must not fail. So the method runs the
#	bootstrap again and writes the path again. Each clone step of
#	the bootstrap skips what exists, so the run repairs a bootstrap
#	that stopped early.
#
#	A path that is no worktree of the name is debris from a killed
#	create, and only remove clears it. The cleanup of _create must
#	not run here, because the worktree belongs to the create before
#	this one.
sub _again ( $app, $root, $name, $wt )
{
	my $log = $app->cli->log;
	my $branch =
	    -e "$wt/.git"
	    ? _capture( $app, 'git', '-C', $wt, 'branch', '--show-current' )
	    : undef;
	unless ( defined $branch && $branch eq $name ) {
		$log->error( 'already exists, not a worktree of %s: %s',
			$name, $wt );
		$log->error( 'remove it with: %s worktree remove %s',
			$app->cli->name, $name );
		return EXIT_ERROR;
	}

	unless ( _bootstrap( $app, $root, $wt ) ) {
		$log->error( 'the bootstrap of %s failed: %s',
			$wt, $app->error );
		return EXIT_ERROR;
	}

	say $wt;

	return EXIT_SUCCESS;
}

# _outside($app, $base, $name, $wt):
#	True when no existing worktree holds the new one
#	(WT-CREATE-2). The removal of an outer worktree destroys an
#	inner one, and it reports nothing. An empty parent directory
#	of a sibling holds no .git, so two worktrees under one plain
#	parent are permitted.
sub _outside ( $app, $base, $name, $wt )
{
	my $dir = dirname($wt);
	while ( length($dir) > length($base) ) {
		if ( -e "$dir/.git" ) {
			$app->cli->log->error(
				'%s nests inside the worktree %s',
				$name, $dir );
			return 0;
		}
		$dir = dirname($dir);
	}

	return 1;
}

# _bootstrap($app, $root, $wt):
#	Run the bootstrap target of the worktree (WT-CREATE-4). The
#	target belongs to the repository, and it names the paths to
#	clone. A worktree with no makefile needs no bootstrap.
sub _bootstrap ( $app, $root, $wt )
{
	return 1 unless grep { -f "$wt/$_" } MAKEFILES;

	return
	    defined $app->command(
		[ 'make', '-C', $wt, 'bootstrap', "MAIN=$root" ],
		group => 1 );
}

# _cleanup($app, $root, $base, $name, $wt):
#	Remove all that create made (WT-CREATE-6). Every step runs,
#	also after a step that fails: the worktree removal, the
#	directory removal, the branch deletion, the prune of the git
#	records, and the prune of each empty parent.
sub _cleanup ( $app, $root, $base, $name, $wt )
{
	$app->command( [
			'git',    '-C',      $root,     'worktree',
			'remove', '--force', '--force', $wt
		] ) if -d $wt;

	if ( -d $wt ) {
		File::Path::remove_tree( $wt, { error => \my $failed } );
		$app->cli->log->error( 'cannot remove %s', $wt )
		    if @{ $failed // [] };
	}

	_delete_branch( $app, $root, $name );
	$app->command( [ 'git', '-C', $root, 'worktree', 'prune' ] );
	_prune_parents( $base, $wt );

	return;
}

# _list($app, @argv):
#	Report each worktree of the base with its name, its age in
#	days, and its state (WT-LIST-1). An operator reads the state
#	to see which worktree is safe to remove, because no hook
#	removes one.
sub _list ( $app, @argv )
{
	return $app->cli->command_usage_error('worktree') if @argv;

	my ( $code, $root, $base ) = _setup($app);
	return $code if $code != EXIT_SUCCESS;

	my $out = $app->command(
		[ 'git', '-C', $root, 'worktree', 'list', '--porcelain' ] );
	unless ( defined $out ) {
		$app->cli->log->error( 'cannot list the worktrees: %s',
			$app->error );
		return EXIT_ERROR;
	}

	my @paths;
	for my $line ( split /\n/, $out ) {
		next unless $line =~ /\Aworktree (.+)\z/;
		my $path = $1;
		push @paths, $path if rindex( $path, "$base/", 0 ) == 0;
	}
	unless (@paths) {
		say 'no worktrees';
		return EXIT_SUCCESS;
	}

	for my $path ( sort @paths ) {

		# The gitfile records the creation, and later work
		# leaves it alone, so its mtime is the age.
		my @stat  = stat "$path/.git";
		my $age   = @stat ? int( ( time - $stat[9] ) / 86_400 ) : -1;
		my @risk  = _risks( $app, $path );
		my $state = @risk ? join( '; ', @risk ) : 'clean';
		say sprintf LINE, substr( $path, length($base) + 1 ),
		    $age < 0 ? '?' : $age, $state;
	}

	return EXIT_SUCCESS;
}

# _risks($app, $wt):
#	Each reason why one worktree holds work at risk
#	(WT-REMOVE-2). An empty list names a worktree that is safe to
#	remove. Each string names one repository and one cause.
sub _risks ( $app, $wt )
{
	my @risk;
	for my $repo ( _repos_in($wt) ) {
		my $rel = $repo eq $wt ? '.' : substr( $repo, length($wt) + 1 );

		my $dirty = _capture( $app, 'git', '-C', $repo, 'status',
			'--porcelain' );
		push @risk, "$rel: uncommitted change"
		    if defined $dirty && length $dirty;

		# Without a remote, a commit that the main branch
		# holds is safe: the merge to main is where the work
		# lands.
		#
		# A linked worktree shares one ref store with its main
		# checkout, so --branches counts the branch of every
		# other worktree too. Its own HEAD is the one ref that
		# it owns. A nested clone is a repository of its own,
		# so --branches is right for it.
		my $linked  = -f "$repo/.git";
		my $remotes = _capture( $app, 'git', '-C', $repo, 'remote' );
		my @not     = ('--remotes');
		push @not, 'main'
		    if !( defined $remotes && length $remotes )
		    && _branch_exists( $app, $repo, 'main' );

		my $count =
		    _capture( $app, 'git', '-C', $repo, 'rev-list', '--count',
			$linked ? 'HEAD' : '--branches',
			'--not', @not );
		push @risk, "$rel: $count commit(s) that no remote holds"
		    if defined $count && $count =~ /\A\d+\z/ && $count > 0;
	}

	return @risk;
}

# _repos_in($wt):
#	Each git repository in one worktree: the worktree itself, and
#	each repository below it, such as a clone under Projects/ or
#	the library at Wiki/ (WT-REMOVE-3). The walk stops at each
#	repository that it finds, because the content of a clone is
#	the business of that clone. It skips scratch/ and a nested
#	worktree directory, which hold no session work.
sub _repos_in ($wt)
{
	my @repos = ($wt);
	File::Find::find( {
			no_chdir   => 1,
			preprocess => sub {
				my @kept = sort
				    grep { $_ ne '.git' && $_ ne 'scratch' } @_;

				return @kept;
			},
			wanted => sub {
				my $name = $File::Find::name;
				return if $name eq $wt;
				return unless -d $name && !-l $name;
				if ( $name =~ m{(?:\A|/)[.]claude/worktrees\z} )
				{
					$File::Find::prune = 1;
					return;
				}
				return unless -e "$name/.git";
				push @repos, $name;
				$File::Find::prune = 1;

				return;
			},
		},
		$wt
	);

	return @repos;
}

# _delete_branch($app, $root, $branch):
#	Delete one branch, and report nothing about a branch that is
#	gone. The method never deletes main, and never the branch that
#	the main checkout has checked out (WT-REMOVE-5). A parallel
#	remove that deletes the branch first is no error. The method
#	returns 0 when the branch stays.
sub _delete_branch ( $app, $root, $branch )
{
	return 1
	    unless defined $branch && length $branch && $branch ne 'main';

	my $head = _capture( $app, 'git', '-C', $root, 'symbolic-ref',
		'--quiet', '--short', 'HEAD' );
	return 1 if defined $head && $branch eq $head;
	return 1 unless _branch_exists( $app, $root, $branch );

	return 1
	    if defined $app->command(
		[ 'git', '-C', $root, 'branch', '-D', $branch ] );
	return 1 unless _branch_exists( $app, $root, $branch );

	$app->cli->log->error( 'cannot delete the branch %s', $branch );

	return 0;
}

# _branch_exists($app, $repo, $branch):
#	True when the repository holds the branch.
sub _branch_exists ( $app, $repo, $branch )
{
	return defined $app->command( [
		'git',      '-C',
		$repo,      'show-ref',
		'--verify', '--quiet',
		"refs/heads/$branch"
	] );
}

# _prune_parents($base, $wt):
#	Remove each empty parent directory of one worktree, up to the
#	base (WT-REMOVE-7). A name with a slash sits in a nested
#	directory, and the first parent that holds a file stops the
#	walk.
sub _prune_parents ( $base, $wt )
{
	my $dir = dirname($wt);
	while ( length($dir) > length($base)
		&& rindex( $dir, "$base/", 0 ) == 0 )
	{
		rmdir $dir or last;
		$dir = dirname($dir);
	}

	return;
}

# _capture($app, @cmd):
#	The standard output of one child, without the last newline,
#	or undef when the child fails.
sub _capture ( $app, @cmd )
{
	my $out = $app->command( \@cmd );
	return unless defined $out;
	chomp $out;

	return $out;
}

1;
