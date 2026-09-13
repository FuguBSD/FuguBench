#!/usr/bin/env perl
# ex:ts=8 sw=4:
# The report of the doctor verb, and its fix (CLI-DOCTOR).
#
# Each case runs bin/fugubench as a child with -Ilib, and it writes
# inside its temporary tree only. The child reads that tree as its
# home, and it reads no system configuration of git, so no case reads
# the operator home and no case reaches the network. The origin of a
# library fixture is a bare repository of the tree, behind a file URL.

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Test::More;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin    qw($RealBin);
use JSON::PP   ();
use lib "$RealBin/../../lib";

use Fugu::Curl;
use Fugu::File;
use Fugu::Process;

my $root    = "$RealBin/../..";
my $program = "$root/bin/fugubench";

plan skip_all => 'git is absent'
    unless Fugu::Process->find_command('git');

# The four events of the hook verb (HOOK-EVENTS-1), in the order of
# the report.
my @EVENTS = qw(SessionEnd SessionStart WorktreeCreate WorktreeRemove);

# The decoder and the encoder of one settings file.
my $JSON = JSON::PP->new->utf8->canonical->pretty;

# _env($tree, %extra):
#	The environment of one child. The child reads the temporary
#	tree as its home, so it reads no operator identity and no
#	signing agent of the operator. The child gets this environment
#	in place of the environment of the test, so this environment
#	must carry PERL5LIB. CI installs Fugu into a local library, and
#	names that library in PERL5LIB.
sub _env ( $tree, %extra )
{
	my %env = (
		PATH                => $ENV{PATH},
		HOME                => $tree,
		GIT_CONFIG_NOSYSTEM => 1,
	);

	# An undefined value is an error, and a host that installs
	# Fugu in the default @INC sets no PERL5LIB.
	$env{PERL5LIB} = $ENV{PERL5LIB} if defined $ENV{PERL5LIB};

	return { %env, %extra };
}

# _write($path, $text):
#	Write one file, and make its parent directories.
sub _write ( $path, $text )
{
	make_path( $path =~ s{/[^/]+\z}{}r );
	Fugu::File->write( $path, $text ) or die "write $path";

	return;
}

# _run_git($tree, @args):
#	Run git with the home of one tree, and return the result of
#	Fugu::Process->run.
sub _run_git ( $tree, @args )
{
	return Fugu::Process->run( cmd => [ 'git', @args ], env => _env($tree) );
}

# _git($tree, @args):
#	Run git with the home of one tree, and die on a failure.
sub _git ( $tree, @args )
{
	my $result = _run_git( $tree, @args );
	die "git @args: $result->{stderr}" unless $result->{success};

	return $result->{stdout};
}

# _checkout($tree, $text):
#	A checkout of the tree, with the .toolingrc of the caller.
sub _checkout ( $tree, $text )
{
	my $dir = "$tree/co";
	_write( "$dir/.toolingrc", $text );

	return $dir;
}

# _tree():
#	A temporary tree with a git identity of its own, and a bare
#	repository with one commit on main as its origin.
sub _tree ()
{
	my $tree = tempdir( CLEANUP => 1 );
	_write( "$tree/.gitconfig", <<'CONFIG' );
[user]
	name = a
	email = a@b
[commit]
	gpgsign = false
CONFIG

	my $origin = "$tree/origin.git";
	_git( $tree, 'init', '--quiet', '--bare', $origin );
	_git( $tree, '-C', $origin, 'symbolic-ref', 'HEAD', 'refs/heads/main' );

	my $seed = "$tree/seed";
	_git( $tree, 'clone', '--quiet', $origin, $seed );
	_git( $tree, '-C', $seed, 'commit', '--quiet', '--allow-empty', '-m',
		'Initial commit' );
	_git( $tree, '-C', $seed, 'branch', '-M', 'main' );
	_git( $tree, '-C', $seed, 'push', '--quiet', 'origin', 'main' );

	return $tree;
}

# _library($tree):
#	A checkout whose .toolingrc names the origin of the tree, and
#	a clone of that origin as its library. The checkout is the
#	home of wiki.origin, so the library is <checkout>/Wiki, the
#	wiki.dir default. The checkout and the library, in that order.
sub _library ($tree)
{
	my $dir = _checkout( $tree, "wiki.origin\tfile://$tree/origin.git\n" );
	_git( $tree, 'clone', '--quiet', "$tree/origin.git", "$dir/Wiki" );

	return ( $dir, "$dir/Wiki" );
}

# _race($tree, $dir, $page, $text):
#	Stop a rebase of the library over one page. The clone commits
#	the text of the caller, a peer pushes a page of that name
#	first, and the rebase of the clone then stops on the add/add
#	conflict. That is the race of the open subcommand.
sub _race ( $tree, $dir, $page, $text )
{
	my $library = "$dir/Wiki";
	_write( "$library/$page", $text );
	_git( $tree, '-C', $library, 'add', $page );
	_git( $tree, '-C', $library, 'commit', '--quiet', '-m', "open: $page" );

	my $peer = "$tree/peer";
	_git( $tree, 'clone', '--quiet', "$tree/origin.git", $peer );
	_write( "$peer/$page", <<"PAGE" );
# Session peer

## Observations

Claim: the peer pushed first.
PAGE
	_git( $tree, '-C', $peer, 'add', $page );
	_git( $tree, '-C', $peer, 'commit', '--quiet', '-m', 'open: the peer' );
	_git( $tree, '-C', $peer, 'push', '--quiet', 'origin', 'main' );

	_git( $tree, '-C', $library, 'fetch', '--quiet', 'origin' );
	die 'the rebase did not stop'
	    if _run_git( $tree, '-C', $library, 'rebase', 'origin/main' )
	    ->{success};

	return $library;
}

# _stopped($library):
#	True while the clone sits in a stopped rebase. git holds the
#	state of one under its git directory.
sub _stopped ($library)
{
	return -d "$library/.git/rebase-merge"
	    || -d "$library/.git/rebase-apply";
}

# _fugubench($tree, $dir, $env, @argv):
#	Run one verb on one checkout, and return the result of
#	Fugu::Process->run. The environment of the caller reaches the
#	child on top of the shared one.
sub _fugubench ( $tree, $dir, $env, @argv )
{
	my $result = Fugu::Process->run(
		cmd => [ $^X, "-I$root/lib", $program, '-C', $dir, @argv ],
		env => _env( $tree, %$env ),
	);
	die "cannot run $program: $result->{error}\n"
	    if defined $result->{error};

	return $result;
}

# _doctor($tree, $dir, $env, @argv):
#	Run the doctor verb, and return the result and the lines of
#	its report, in that order.
sub _doctor ( $tree, $dir, $env, @argv )
{
	my $result = _fugubench( $tree, $dir, $env, 'doctor', @argv );

	return ( $result, [ split /\n/, $result->{stdout} ] );
}

# _line($lines, $check):
#	The report line of one check, or a string that names the
#	absent line. Each line holds the check between the state and
#	the detail.
sub _line ( $lines, $check )
{
	my ($line) = grep { index( $_, " $check: " ) > 0 } @$lines;

	return $line // "no line of $check";
}

# _tool_line($name):
#	The expected line of one tool of the report. A gate host holds
#	git and make, and a host without one of them must read the
#	problem line.
sub _tool_line ($name)
{
	my $path = Fugu::Process->find_command($name);

	return defined $path
	    ? "ok $name: $path"
	    : "problem $name: absent from PATH";
}

# _settings($path, $change):
#	Read the settings file, pass it to the change of the caller,
#	and write it again.
sub _settings ( $path, $change )
{
	my $text = Fugu::File->read($path);
	die "read $path" unless defined $text;

	my $settings = $JSON->decode($text);
	$change->($settings);
	_write( $path, $JSON->encode($settings) );

	return;
}

subtest 'the report of a checkout with no hook and no library' => sub {
	my $tree = tempdir( CLEANUP => 1 );
	my $dir  = _checkout( $tree, "wiki.project\tBench\n" );

	# The version detail is the line of the version verb, and the
	# two must never disagree.
	my $version =
	    _fugubench( $tree, $dir, {}, 'version' )->{stdout} =~ s/\n\z//r;

	my ( $r, $lines ) = _doctor( $tree, $dir, {} );
	is( scalar @$lines, 6, 'the report holds one line for each check' )
	    or diag $r->{stdout};
	is( $lines->[0], "ok version: $version",
		'the version line is the line of the version verb' );
	is( $lines->[1], _tool_line('git'), 'the git line names its path' );
	is( $lines->[2], _tool_line('make'), 'the make line names its path' );

	my $downloader = Fugu::Curl->new->command;
	is(
		$lines->[3],
		defined $downloader
		? "ok downloader: $downloader"
		: 'problem downloader: no curl, wget, or ftp on PATH',
		'the downloader line names the first of the three'
	);
	is( $lines->[4], 'ok hooks: none',
		'a checkout with no settings file holds no hook entry' );
	is( $lines->[5], 'ok library: absent',
		'a checkout with no wiki.origin holds no library' );

	# The exit code follows the report (CLI-DOCTOR-3).
	my $problems = grep { index( $_, 'problem ' ) == 0 } @$lines;
	is( $r->{exit_code}, $problems ? 1 : 0,
		'the exit code follows the report' );
	is( $r->{stderr}, q{}, 'a report of ok lines writes no diagnostic' );
};

subtest 'a PATH with git alone names each absent tool' => sub {
	my $tree = tempdir( CLEANUP => 1 );
	my $dir  = _checkout( $tree, "wiki.project\tBench\n" );

	my $bin = "$tree/bin";
	make_path($bin);
	symlink Fugu::Process->find_command('git'), "$bin/git"
	    or die "symlink $bin/git";

	my ( $r, $lines ) = _doctor( $tree, $dir, { PATH => $bin } );
	is( _line( $lines, 'git' ), "ok git: $bin/git",
		'the git line names the path of that PATH' );
	is( _line( $lines, 'make' ), 'problem make: absent from PATH',
		'an absent make is a problem' );
	is(
		_line( $lines, 'downloader' ),
		'problem downloader: no curl, wget, or ftp on PATH',
		'a PATH with no downloader is a problem'
	);
	is( $r->{exit_code}, 1, 'a problem line makes the exit code 1' );
};

subtest 'the hook entries of the settings file' => sub {
	my $tree = tempdir( CLEANUP => 1 );
	my $dir  = _checkout( $tree, "wiki.project\tBench\n" );
	my $path = "$dir/.claude/settings.json";

	# A settings file of other keys holds no event of the four.
	_write( $path, qq[{ "permissions": { "allow": [] } }\n] );
	my ( $r, $lines ) = _doctor( $tree, $dir, {} );
	is( _line( $lines, 'hooks' ), 'ok hooks: none',
		'a file with no event of the four holds no hook entry' );

	is( _fugubench( $tree, $dir, {}, 'hook', 'install' )->{exit_code},
		0, 'the install writes the entries' );

	( $r, $lines ) = _doctor( $tree, $dir, {} );
	is( scalar @$lines, 9, 'the report holds one line for each event' )
	    or diag $r->{stdout};
	is( _line( $lines, "hook $_" ), "ok hook $_: installed",
		"$_ is the entry of hook install" )
	    for @EVENTS;
	is( $r->{exit_code}, 0, 'a file after the install exits zero' );

	# A changed timeout is no entry of hook install (HOOK-INSTALL-3).
	_settings( $path,
		sub ($s) { $s->{hooks}{SessionStart}[0]{hooks}[0]{timeout} = 5 }
	);
	( $r, $lines ) = _doctor( $tree, $dir, {} );
	is(
		_line( $lines, 'hook SessionStart' ),
		'problem hook SessionStart: differs from hook install',
		'a changed timeout is a problem'
	);
	is( _line( $lines, 'hook SessionEnd' ), 'ok hook SessionEnd: installed',
		'the change reaches one line alone' );
	is( $r->{exit_code}, 1, 'a changed entry makes the exit code 1' );

	# An event that the file lost is absent, and the three that
	# stay keep their lines.
	_settings( $path, sub ($s) { delete $s->{hooks}{WorktreeRemove} } );
	( $r, $lines ) = _doctor( $tree, $dir, {} );
	is( _line( $lines, 'hook WorktreeRemove' ),
		'problem hook WorktreeRemove: absent',
		'an event that the file lost is absent' );
	is( _line( $lines, 'hook WorktreeCreate' ),
		'ok hook WorktreeCreate: installed',
		'an event that stays keeps its line' );

	# A file that hook install cannot extend stops that install.
	_write( $path, qq[{ "hooks": }\n] );
	( $r, $lines ) = _doctor( $tree, $dir, {} );
	is( _line( $lines, 'hooks' ), "problem hooks: $path holds no JSON object",
		'a file that does not parse is a problem' );
	is( $r->{exit_code}, 1, 'that file makes the exit code 1' );

	_write( $path, qq[{ "hooks": [] }\n] );
	( $r, $lines ) = _doctor( $tree, $dir, {} );
	is(
		_line( $lines, 'hooks' ),
		"problem hooks: $path: the hooks key holds no object",
		'a hooks key of another kind is a problem'
	);
};

subtest 'a clone that holds a change' => sub {
	my $tree = _tree();
	my ( $dir, $library ) = _library($tree);

	my ( $r, $lines ) = _doctor( $tree, $dir, {} );
	is( _line( $lines, 'library' ), "ok library: $library",
		'a clean clone gives its path' );
	is( $r->{exit_code}, 0, 'a clean clone exits zero' );

	_write( "$library/Notes.md", "# Notes\n" );
	_git( $tree, '-C', $library, 'add', 'Notes.md' );
	( $r, $lines ) = _doctor( $tree, $dir, {} );
	is( _line( $lines, 'library' ), 'problem library: changes Notes.md',
		'an uncommitted change names its file' );
	is( $r->{exit_code}, 1, 'a change makes the exit code 1' );
};

subtest 'a stopped rebase over a page with no observation' => sub {
	my $tree = _tree();
	my ( $dir, $library ) = _library($tree);
	my $page = 'Session-Bench-2026-09-13-1.md';
	_race( $tree, $dir, $page, <<"PAGE" );
# Session Bench 2026-09-13 1

Session: a-b-c
Project: Bench
Opened: 2026-09-13T00:00:00Z

## Observations
PAGE

	my ( $r, $lines ) = _doctor( $tree, $dir, {} );
	is(
		_line( $lines, 'library' ),
		"problem library: stopped rebase, the pending commit adds $page",
		'the report names the page of the pending commit'
	);
	is( $r->{exit_code}, 1, 'a stopped rebase makes the exit code 1' );
	ok( _stopped($library), 'the report leaves the rebase' );

	( $r, $lines ) = _doctor( $tree, $dir, {}, '--fix' );
	is(
		_line( $lines, 'library' ),
		"ok library: skipped the pending commit $page",
		'the fix skips the pending commit'
	);
	is( $r->{exit_code}, 0, 'the fix exits zero' );
	ok( !_stopped($library), 'the fix ends the rebase' );

	# The message of git is no part of the report (CLI-PROGRAM-4).
	unlike( $r->{stdout}, qr/rebase/i, 'git writes no line of the report' );
	like( $r->{stderr}, qr/\S/, 'git writes to standard error' );

	( $r, $lines ) = _doctor( $tree, $dir, {} );
	is( _line( $lines, 'library' ), "ok library: $library",
		'the next run reports a clean clone' );

	# The fix keeps the page of the peer, and it drops the page of
	# the commit that lost the race.
	like( Fugu::File->read("$library/$page"),
		qr/the peer pushed first/, 'the page of the peer stays' );
};

subtest 'a pending commit that carries work refuses the fix' => sub {
	my $tree = _tree();
	my ( $dir, $library ) = _library($tree);
	my $page = 'Session-Bench-2026-09-13-1.md';
	_race( $tree, $dir, $page, <<"PAGE" );
# Session Bench 2026-09-13 1

## Observations

Claim: this session captured work.
PAGE

	my ( $r, $lines ) = _doctor( $tree, $dir, {}, '--fix' );
	is(
		_line( $lines, 'library' ),
		"problem library: stopped rebase, fix refused:"
		    . " $page holds an observation",
		'a page with an observation refuses the fix'
	);
	is( $r->{exit_code}, 1, 'the refusal makes the exit code 1' );
	ok( _stopped($library), 'the refusal leaves the rebase' );
};

subtest 'a pending commit of another shape refuses the fix' => sub {
	my $tree = _tree();
	my ( $dir, $library ) = _library($tree);
	my $page = 'Session-Bench-2026-09-13-1.md';

	# The commit adds a second file, so it is no commit of the
	# race, and the report names each file of it.
	_write( "$library/Notes.md", "# Notes\n" );
	_git( $tree, '-C', $library, 'add', 'Notes.md' );
	_race( $tree, $dir, $page, "# Session Bench\n\n## Observations\n" );

	my ( $r, $lines ) = _doctor( $tree, $dir, {}, '--fix' );
	is(
		_line( $lines, 'library' ),
		'problem library: stopped rebase, fix refused:'
		    . " the pending commit changes Notes.md, $page",
		'a commit of two files refuses the fix'
	);
	ok( _stopped($library), 'the refusal leaves the rebase' );

	( $r, $lines ) = _doctor( $tree, $dir, {} );
	is(
		_line( $lines, 'library' ),
		'problem library: stopped rebase,'
		    . " the pending commit changes Notes.md, $page",
		'the report without the fix names each file'
	);
};

done_testing();
