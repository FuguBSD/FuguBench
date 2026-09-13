#!/usr/bin/env perl
# ex:ts=8 sw=4:
# The count of the pages, the rename of a page that the origin took,
# the append of one capture, and the push of the wiki verb
# (WIKI-OPEN-2, WIKI-OPEN-3, WIKI-CAPTURE-1, WIKI-CAPTURE-4,
# WIKI-CAPTURE-5, WIKI-CAPTURE-6).
#
# On 2026-09-09 two parallel sessions of one day took one page name,
# and the rebase of the loser stopped on an add/add conflict. So each
# case here runs two checkouts against one bare repository, and it
# takes the race that the program must settle.
#
# Each case runs bin/fugubench as a child with -Ilib. The child reads
# the temporary tree as its home, and it reads no system
# configuration, so no case reads the operator home and no case
# reaches the network.

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin    qw($RealBin);
use POSIX      qw(strftime);
use lib "$RealBin/../../lib";

use Fugu::File;
use Fugu::Process;

my $root    = "$RealBin/../..";
my $program = "$root/bin/fugubench";

plan skip_all => 'git is absent'
    unless Fugu::Process->find_command('git');

my $today = strftime( '%Y-%m-%d', gmtime );

# _env($home):
#	The environment of one child. The child reads the temporary
#	tree as its home, so it reads no operator identity and no
#	signing agent of the operator.
sub _env ($home)
{
	return {
		PATH                => $ENV{PATH},
		HOME                => $home,
		GIT_CONFIG_NOSYSTEM => 1,
	};
}

# _write($path, $text, %args):
#	Write one file, and make its parent directories.
sub _write ( $path, $text, %args )
{
	make_path( $path =~ s{/[^/]+\z}{}r );
	Fugu::File->write( $path, $text, %args ) or die "write $path";

	return;
}

# _git($home, @args):
#	Run git with the home of one tree, and die on a failure.
sub _git ( $home, @args )
{
	my $result = Fugu::Process->run(
		cmd => [ 'git', @args ],
		env => _env($home),
	);
	die "git @args: $result->{stderr}" unless $result->{success};

	return $result->{stdout};
}

# _tree():
#	A temporary tree with a git identity of its own, and a bare
#	repository with one commit on main as the origin. The tree and
#	the path of the origin, in that order.
#
#	The origin refuses a push that is no fast-forward, as the
#	ruleset of the library does.
sub _tree ()
{
	my $dir = tempdir( CLEANUP => 1 );
	_write( "$dir/.gitconfig", <<'CONFIG' );
[user]
	name = a
	email = a@b
[commit]
	gpgsign = false
CONFIG

	my $origin = "$dir/origin.git";
	_git( $dir, 'init', '--quiet', '--bare', $origin );
	_git( $dir, '-C', $origin, 'symbolic-ref', 'HEAD', 'refs/heads/main' );
	_git( $dir, '-C', $origin, 'config', 'receive.denyNonFastForwards',
		'true' );

	my $seed = "$dir/seed";
	_git( $dir, 'clone', '--quiet', $origin, $seed );
	_git( $dir, '-C', $seed, 'commit', '--quiet', '--allow-empty', '-m',
		'Initial commit' );
	_git( $dir, '-C', $seed, 'branch', '-M', 'main' );
	_git( $dir, '-C', $seed, 'push', '--quiet', 'origin', 'main' );

	return ( $dir, $origin );
}

# _checkout($tree, $origin, $name):
#	A checkout of the tree with a clone of the library. The
#	checkout names the origin in its .toolingrc, so init clones it.
sub _checkout ( $tree, $origin, $name )
{
	my $dir = "$tree/$name";
	_write( "$dir/.toolingrc", "wiki.origin\tfile://$origin\n" );
	my $r = _run( $tree, $dir, 'init' );
	die "init $name: $r->{stderr}" unless $r->{exit_code} == 0;

	return $dir;
}

# _child($tree, @argv):
#	Run the program as a child with the environment of one tree,
#	and return the result of Fugu::Process->run.
sub _child ( $tree, @argv )
{
	my $result = Fugu::Process->run(
		cmd => [ $^X, "-I$root/lib", $program, @argv ],
		env => _env($tree),
	);
	die "cannot run $program: $result->{error}\n"
	    if defined $result->{error};

	return $result;
}

# _run($tree, $dir, @args):
#	Run the wiki verb against one checkout.
sub _run ( $tree, $dir, @args )
{
	return _child( $tree, '-C', $dir, 'wiki', @args );
}

# _pages($tree, $origin):
#	Each page of the main branch of the origin, in sorted order.
sub _pages ( $tree, $origin )
{
	my $out = _git( $tree, '-C', $origin, 'ls-tree', '--name-only',
		'main' );

	return sort grep { /[.]md\z/ } split /\n/, $out;
}

# _page($n):
#	The name of the session page of the day, with one index.
sub _page ($n)
{
	return "Session-P-$today-$n.md";
}

subtest 'the count reads the origin and the working tree' => sub {
	my ( $tree, $origin ) = _tree();
	my $one = _checkout( $tree, $origin, 'c1' );
	my $two = _checkout( $tree, $origin, 'c2' );

	my $r = _run( $tree, $two, 'open', 'P', 'sess-2' );
	is( $r->{stdout}, _page(1) . "\n", 'the first clone takes the index 1' )
	    or diag $r->{stderr};

	# The first clone cloned before that page arrived, so its
	# working tree alone holds no page of the day (WIKI-OPEN-2).
	$r = _run( $tree, $one, 'open', 'P', 'sess-1' );
	is( $r->{exit_code}, 0, 'the stale clone exits 0' );
	is( $r->{stdout}, _page(2) . "\n",
		'the stale clone takes the next index' );
	unlike( $r->{stderr}, qr/rebasing and retrying/,
		'the push of the stale clone needs no retry' );
	is_deeply( [ _pages( $tree, $origin ) ],
		[ _page(1), _page(2) ], 'the origin holds both pages' );

	# The session identifier lives in the page, so a second open of
	# one session takes no index (WIKI-OPEN-1, WIKI-PAGES-4).
	$r = _run( $tree, $one, 'open', 'P', 'sess-1' );
	is( $r->{exit_code}, 0, 'a second open exits 0' );
	is( $r->{stdout}, _page(2) . "\n",
		'a second open writes the same page' );
	like( $r->{stderr}, qr/already open/,
		'a second open reports the page' );
	is_deeply( [ _pages( $tree, $origin ) ],
		[ _page(1), _page(2) ], 'a second open adds no page' );
};

subtest 'a page name that the origin takes between the fetch and the push' =>
    sub {
	my ( $tree, $origin ) = _tree();
	my $one = _checkout( $tree, $origin, 'c1' );
	my $two = _checkout( $tree, $origin, 'c2' );

	# The peer opens its page inside the push of the first clone.
	# So the origin takes the name after the fetch of that clone,
	# and the push meets a rejection (WIKI-OPEN-3). The marker
	# holds the peer to one run, because the retry pushes again.
	#
	# git gives a hook the variables of its own repository, and the
	# peer runs in another one. So the hook drops them first.
	my $marker = "$tree/peer.done";
	_write(
		"$one/Wiki/.git/hooks/pre-push", <<"HOOK", mode => 0755 );
#!/bin/sh
[ -e '$marker' ] && exit 0
: > '$marker'
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_CONFIG_PARAMETERS
'$^X' '-I$root/lib' '$program' -C '$two' wiki open P sess-2 >/dev/null 2>&1
exit 0
HOOK

	my $r = _child( $tree, '--verbose', '-C', $one, 'wiki', 'open', 'P',
		'sess-1' );
	is( $r->{exit_code}, 0, 'open exits 0 after the rejection' )
	    or diag $r->{stderr};
	ok( -e $marker, 'the peer ran' );
	is( $r->{stdout}, _page(2) . "\n", 'open writes the renamed page' );
	like( $r->{stderr}, qr/rebasing and retrying/, 'the retry ran' );
	is_deeply( [ _pages( $tree, $origin ) ],
		[ _page(1), _page(2) ], 'the origin holds both pages' );

	my $subject =
	    _git( $tree, '-C', "$one/Wiki", 'log', '-1', '--format=%s' );
	is( $subject, 'open: ' . _page(2) . "\n",
		'the commit subject names the renamed page' );

	is( _git( $tree, '-C', "$one/Wiki", 'status', '--porcelain' ),
		q{}, 'the working tree of the clone is clean' );
	ok( !-e "$one/Wiki/.git/rebase-merge",
		'no stopped rebase stays behind' );
	ok( -e "$one/Wiki/" . _page(1),
		'the rebase brings the page of the peer into the clone' );

	# A ruleset of the library forbids a forced push, so no git
	# call of the retry carries one (WIKI-CAPTURE-5).
	my @forced = grep { /^\[[^]]*\] INFO: run: git .*(?:--force|\s-f\b)/ }
	    split /\n/, $r->{stderr};
	is( "@forced", q{}, 'no traced git command forces a push' );
    };

subtest 'two clones append to one page, and the rebase of the loser stops' =>
    sub {
	my ( $tree, $origin ) = _tree();
	my $one = _checkout( $tree, $origin, 'c1' );

	my $r = _run( $tree, $one, 'open', 'P', 'sess-1' );
	is( $r->{exit_code}, 0, 'open exits 0' ) or diag $r->{stderr};

	# The peer clones after the push of the page, so both clones
	# hold the page, and both append to its end.
	my $two = _checkout( $tree, $origin, 'c2' );

	_write( "$tree/peer.md", "Claim: the peer writes first.\n" );
	$r = _run( $tree, $two, 'note', _page(1), "$tree/peer.md" );
	is( $r->{exit_code}, 0, 'the peer notes and pushes' )
	    or diag $r->{stderr};
	is( $r->{stdout}, _page(1) . "\n", 'note writes the page name' );
	like(
		Fugu::File->read( "$two/Wiki/" . _page(1) ),
		qr/^[#][#] Observations\n\nClaim: the peer writes first[.]\n\z/m,
		'the append leaves one blank line (WIKI-CAPTURE-1)'
	);

	# The clone of the first checkout is behind now, so its push
	# meets a rejection. The rebase of its commit stops, because
	# both commits append to the end of one page.
	_write( "$tree/obs.md", "Claim: the loser writes second.\n" );
	$r = _child( $tree, '--verbose', '-C', $one, 'wiki', 'note',
		_page(1), "$tree/obs.md" );
	is( $r->{exit_code}, 0, 'the loser exits 0 (WIKI-CAPTURE-4)' );
	is( $r->{stdout}, _page(1) . "\n", 'the loser writes the page name' );
	like( $r->{stderr}, qr/rebasing and retrying/, 'the retry ran' );
	like( $r->{stderr}, qr/the rebase stopped/, 'the rebase stopped' );
	like( $r->{stderr}, qr/push failed, the commit stays local/,
		'the loser warns' );

	ok( !-e "$one/Wiki/.git/rebase-merge",
		'no stopped rebase stays behind' );
	is( _git( $tree, '-C', "$one/Wiki", 'status', '--porcelain' ),
		q{}, 'the working tree of the clone is clean' );
	is(
		_git(
			$tree, '-C', "$one/Wiki", 'rev-list',
			'--count', 'HEAD', '--not', '--remotes'
		),
		"1\n",
		'one commit stays unpushed'
	);

	# A ruleset of the library forbids a forced push, so no git
	# call of the capture carries one (WIKI-CAPTURE-5).
	my @forced = grep { /^\[[^]]*\] INFO: run: git .*(?:--force|\s-f\b)/ }
	    split /\n/, $r->{stderr};
	is( "@forced", q{}, 'no traced git command forces a push' );

	my $page = _page(1);
	my $log  = _git( $tree, '-C', $origin, 'log', '--format=%s' );
	like( $log, qr/^note: \Q$page\E$/m,
		'the origin holds the note of the peer' );
	unlike(
		_git( $tree, '-C', $origin, 'show', 'main:' . _page(1) ),
		qr/the loser writes second/,
		'the note of the loser stays local'
	);
    };

subtest 'a detached HEAD commits and pushes nothing' => sub {
	my ( $tree, $origin ) = _tree();
	my $one = _checkout( $tree, $origin, 'c1' );

	my $r = _run( $tree, $one, 'open', 'P', 'sess-1' );
	is( $r->{exit_code}, 0, 'open exits 0' ) or diag $r->{stderr};

	# A detached HEAD names no branch, so the push has no target
	# (WIKI-CAPTURE-6). The commit still carries the durability.
	_git( $tree, '-C', "$one/Wiki", 'checkout', '--quiet', '--detach' );
	my $head = _git( $tree, '-C', $origin, 'rev-parse', 'main' );

	_write( "$tree/obs.md", "Claim: the head is detached.\n" );
	$r = _run( $tree, $one, 'note', _page(1), "$tree/obs.md" );
	is( $r->{exit_code}, 0, 'note exits 0 with a detached HEAD' )
	    or diag $r->{stderr};
	is( $r->{stdout}, _page(1) . "\n", 'note writes the page name' );
	like( $r->{stderr}, qr/detached HEAD, not pushing/, 'note warns' );

	is( _git( $tree, '-C', "$one/Wiki", 'log', '-1', '--format=%s' ),
		'note: ' . _page(1) . "\n", 'the commit carries the note' );
	is( _git( $tree, '-C', "$one/Wiki", 'status', '--porcelain' ),
		q{}, 'the working tree of the clone is clean' );
	is( _git( $tree, '-C', $origin, 'rev-parse', 'main' ),
		$head, 'the origin does not change' );
};

done_testing();
