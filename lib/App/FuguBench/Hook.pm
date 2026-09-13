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

package App::FuguBench::Hook;

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Cwd        ();
use File::Spec ();
use JSON::PP   ();

use Fugu::CLI qw(EXIT_SUCCESS EXIT_ERROR);

use App::FuguBench::Checkout;
use App::FuguBench::Wiki;
use App::FuguBench::Worktree;

# App::FuguBench::Hook - the hook verb.
#
# The verb answers one hook event of Claude Code. The harness writes
# a JSON payload to standard input, and the verb reads that payload
# itself, so no hook command needs jq (D-07). The events are
# SessionStart, SessionEnd, WorktreeCreate, and WorktreeRemove. A
# word outside the four is a usage error (HOOK-EVENTS-1).
#
# This verb and the trace verb hold the Claude Code assumptions of
# the program, and every other verb is agent-agnostic (D-10). The
# payload shape lives here, and in no shared module.
#
# The payload comes first, and the checkout after. The verb builds
# the checkout from the payload cwd, and it sets that checkout on the
# dispatcher (HOOK-EVENTS-5). A session can start in a worktree, and
# a worktree is a checkout with its own library clone. The option -C
# names the root ahead of the payload (CLI-CHECKOUT-1).
#
# The verb runs the other verbs in process. It calls the body of the
# Fugu::CLI entry of a verb with the dispatcher and the arguments, as
# the dispatcher does, so no child perl runs and no option parses
# twice.
#
# A session event must never stop a session, so it maps every
# non-zero code to a warning and returns zero (HOOK-EVENTS-3).
# WorktreeCreate returns the code of worktree create, because the
# harness needs the path of the worktree.

# The events of the verb (HOOK-EVENTS-1).
my %EVENT = (
	SessionStart   => \&_session_start,
	SessionEnd     => \&_session_end,
	WorktreeCreate => \&_worktree_create,
	WorktreeRemove => \&_worktree_remove,
);

# The shape of a project name that comes from a path (WIKI-OPEN-5).
# The name reaches git as an argument of wiki open, and a name that
# starts with a dash reaches git as an option.
my $PROJECT = qr{\A[A-Za-z0-9][A-Za-z0-9._-]*\z};

# The decoder of one payload. It takes the bytes of the payload, and
# it decodes the UTF-8 itself. An :encoding layer loads the
# PerlIO::encoding extension at the first read, and no row of the
# sandbox gives a promise for the load of a shared object.
my $JSON = JSON::PP->new->utf8;

# App::FuguBench::Hook->command($verb):
#	The entry of the Fugu::CLI table. The module holds one verb,
#	so it ignores the name.
sub command ( $, $ )
{
	return {
		summary => 'answer one Claude Code hook event',
		usage   => 'SessionStart | SessionEnd | WorktreeCreate'
		    . ' | WorktreeRemove',
		run => sub ( $app, @argv ) { return _run( $app, @argv ) },
	};
}

# _run($app, @argv):
#	The body of the verb. It reads the event as its first
#	argument, and it takes no other argument.
#
#	The two early exits answer every event with the code zero. A
#	payload that does not parse warns (HOOK-EVENTS-2), and a
#	payload of a sub-agent stops the verb with no change
#	(HOOK-EVENTS-4). An observer dispatches an operator for each
#	step and a verifier for each claim, so without that exit each
#	of them opens a page of its own.
sub _run ( $app, @argv )
{
	my $word  = shift @argv;
	my $event = defined $word ? $EVENT{$word} : undef;
	return $app->cli->command_usage_error('hook') if !$event || @argv;

	my $payload = _payload($app);
	return EXIT_SUCCESS unless $payload;
	return EXIT_SUCCESS if defined $payload->{agent_id};

	return $event->( $app, $payload );
}

# _payload($app):
#	The payload of the event: the whole standard input, decoded as
#	JSON (HOOK-EVENTS-2). The method warns and returns undef when
#	the text is no JSON object.
sub _payload ($app)
{
	# The harness writes the payload to standard input, so the
	# verb reads that handle by name. <> and <ARGV> read the files
	# that @ARGV names, and @ARGV holds the verb and the event.
	my $raw = do {
		## no critic (InputOutput::ProhibitExplicitStdin)
		local $/ = undef;
		<STDIN>;
	};
	my $payload = eval { $JSON->decode( $raw // q{} ) };
	return $payload if ref $payload eq 'HASH';

	$app->cli->log->warning('the hook payload does not parse');

	return;
}

# _checkout($app, $cwd):
#	The checkout of the payload, set on the dispatcher
#	(HOOK-EVENTS-5). The method warns and returns undef when no
#	.toolingrc sits above the cwd.
#
#	The walk starts at the cwd, and it cuts no path at a marker,
#	so a session in a worktree reads the worktree
#	(CLI-CHECKOUT-4).
#
#	With -C the dispatcher owns the start, and the value names the
#	root ahead of the payload (CLI-CHECKOUT-1). The call of the
#	dispatcher reports a walk that finds nothing.
sub _checkout ( $app, $cwd )
{
	return $app->checkout if defined $app->cli->option('C');

	my $checkout = App::FuguBench::Checkout->new( start => $cwd );
	unless ($checkout) {
		$app->cli->log->warning( 'no .toolingrc above %s', $cwd );
		return;
	}

	return $app->checkout($checkout);
}

# _verb($app, $module, $verb, @args):
#	Run one verb of the program in process, and return its exit
#	code. The entry of the Fugu::CLI table holds the body, and the
#	dispatcher runs that same body.
#
#	The call takes the body, and not the wrapper of the
#	dispatcher, so no second sandbox entry runs. The row of the
#	hook verb pledges the promises of every verb that it calls.
sub _verb ( $app, $module, $verb, @args )
{
	return $module->command($verb)->{run}->( $app, @args );
}

# _never_stop($app, $what, $code):
#	Map a non-zero code of one call to a warning, and return zero
#	(HOOK-EVENTS-3). A session event must never stop a session.
#	The verb of the call reported the reason already, so the
#	warning names the call alone.
sub _never_stop ( $app, $what, $code )
{
	$app->cli->log->warning( '%s exited %d', $what, $code )
	    if $code != EXIT_SUCCESS;

	return EXIT_SUCCESS;
}

# _session($app, $payload):
#	The cwd and the session identifier of a session event, in that
#	order. The method warns and returns the empty list when the
#	payload omits one of the two.
#
#	The identifier reaches git through wiki open, so the method
#	replaces each character outside a letter, a digit, a dot, a
#	dash, and an underscore with a dash (HOOK-SESSION-1).
sub _session ( $app, $payload )
{
	my $cwd     = $payload->{cwd};
	my $session = $payload->{session_id};
	unless ( defined $cwd && defined $session ) {
		$app->cli->log->warning(
			'the hook payload names no cwd or no session');
		return;
	}
	$session =~ s/[^A-Za-z0-9._-]/-/g;

	return ( $cwd, $session );
}

# _session_start($app, $payload):
#	Clone the library, and start the session page: wiki init
#	first, and then wiki open (HOOK-SESSION-1).
#
#	The page name of wiki open reaches standard output, and the
#	harness adds that line to the context of the session. init
#	writes the directory of a clone that it makes (WIKI-CLONE-1),
#	and that line comes in front of the page name.
sub _session_start ( $app, $payload )
{
	my ( $cwd, $session ) = _session( $app, $payload );
	return EXIT_SUCCESS unless defined $session;

	my $checkout = _checkout( $app, $cwd );
	return EXIT_SUCCESS unless $checkout;

	_never_stop( $app, 'wiki init',
		_verb( $app, 'App::FuguBench::Wiki', 'wiki', 'init' ) );

	return _never_stop(
		$app,
		'wiki open',
		_verb(
			$app, 'App::FuguBench::Wiki', 'wiki', 'open',
			_project( $app, $checkout, $cwd ), $session
		) );
}

# _session_end($app, $payload):
#	Close the session page (HOOK-SESSION-3). A session with no
#	page is normal, and wiki close reports it.
sub _session_end ( $app, $payload )
{
	my ( $cwd, $session ) = _session( $app, $payload );
	return EXIT_SUCCESS unless defined $session;

	return EXIT_SUCCESS unless _checkout( $app, $cwd );

	return _never_stop(
		$app,
		'wiki close',
		_verb(
			$app, 'App::FuguBench::Wiki', 'wiki', 'close', $session
		) );
}

# _project($app, $checkout, $cwd):
#	The project of the session (HOOK-SESSION-2): the child of the
#	projects directory that holds the cwd, and otherwise the
#	wiki.project value.
#
#	The home of wiki.origin anchors wiki.projects, as it anchors
#	every wiki. value (CLI-CONFIG-2). A checkout with no
#	wiki.origin holds no library, and the key has no home there,
#	so the root anchors the value.
#
#	The value must name a directory below that home
#	(CLI-CONFIG-3), and the child must hold the token shape of
#	wiki open. A value that fails the shape check warns, and the
#	method then gives the wiki.project value.
#
#	The method resolves both paths before the match, because one
#	of them can hold a symbolic link that the other one resolves.
sub _project ( $app, $checkout, $cwd )
{
	my ($project) = $checkout->config('wiki.project');
	my $home = ( $checkout->config('wiki.origin') )[1] // $checkout->root;

	my ($value) = $checkout->config('wiki.projects');
	my $dir = $checkout->dir_value($value);
	unless ( defined $dir ) {
		$app->cli->log->warning( 'wiki.projects: %s',
			$checkout->error );
		return $project;
	}

	my $under = Cwd::abs_path( File::Spec->catdir( $home, $dir ) );
	my $abs   = Cwd::abs_path($cwd);
	return $project unless defined $under && defined $abs;
	return $project unless index( $abs, "$under/" ) == 0;

	my ($child) = split m{/}, substr $abs, length "$under/";

	return defined $child && $child =~ $PROJECT ? $child : $project;
}

# _worktree_create($app, $payload):
#	Make the worktree of the payload, and return the code of
#	worktree create (HOOK-WORKTREE-1). That subcommand writes the
#	path of the worktree to standard output as the only line, and
#	the harness needs that path (WT-CREATE-5).
#
#	So this event returns the code 1 after a failure, where a
#	session event returns zero (HOOK-EVENTS-3). A payload that
#	names no worktree, and a cwd with no checkout above it, both
#	give that code and no path line.
#
#	Claude Code runs the create hook again when a session
#	reconnects, with the same name. The subcommand then bootstraps
#	the worktree again, writes the path again, and returns zero
#	(HOOK-WORKTREE-3, WT-CREATE-7).
sub _worktree_create ( $app, $payload )
{
	my $log  = $app->cli->log;
	my $name = $payload->{name};
	unless ( defined $name ) {
		$log->error('the hook payload names no worktree');
		return EXIT_ERROR;
	}

	my $cwd = $payload->{cwd};
	unless ( defined $cwd ) {
		$log->error('the hook payload names no cwd');
		return EXIT_ERROR;
	}
	return EXIT_ERROR unless _checkout( $app, $cwd );

	return _verb( $app, 'App::FuguBench::Worktree', 'worktree', 'create',
		$name );
}

# _worktree_remove($app, $payload):
#	Keep the worktree, print the manual command, and return zero
#	(HOOK-WORKTREE-2). The event removes nothing (D-06), and it
#	exits zero always (HOOK-EVENTS-3).
#
#	Both lines go to standard error, because the event has no
#	result (CLI-PROGRAM-4).
sub _worktree_remove ( $app, $payload )
{
	my $log  = $app->cli->log;
	my $path = $payload->{worktree_path};
	unless ( defined $path ) {
		$log->warning('the hook payload names no worktree path');
		return EXIT_SUCCESS;
	}

	$log->notice( 'worktree kept: %s', $path );

	# The value goes in a variable first. A call in the argument
	# list runs in list context, and a base that is absent then
	# gives the empty list in place of one argument.
	my $base = _base( $app, $payload );
	my ( $root, $name ) = _split( $path, $base );
	$log->notice( 'to remove it: make -C %s worktree-remove NAME=%s',
		$root, $name )
	    if defined $name;

	return EXIT_SUCCESS;
}

# _base($app, $payload):
#	The worktree.base value of the checkout of the payload, or
#	undef. That value names the segment that splits the worktree
#	path.
#
#	A payload with no cwd, a cwd with no checkout above it, and a
#	value that fails the shape check all give undef. The event
#	then prints the path alone, and it prints no command with a
#	root that it guessed.
sub _base ( $app, $payload )
{
	my $cwd = $payload->{cwd};
	return unless defined $cwd;

	my $checkout = _checkout( $app, $cwd );
	return unless $checkout;

	my ($value) = $checkout->config('worktree.base');
	my $base = $checkout->dir_value($value);
	$app->cli->log->warning( 'worktree.base: %s', $checkout->error )
	    unless defined $base;

	return $base;
}

# _split($path, $base):
#	The root and the name of one worktree path, in that order. The
#	method splits the path at its last <base> segment: the part in
#	front is the root, and the part after is the name. It returns
#	the empty list without a base, without such a segment, and
#	when no name follows the segment.
#
#	The split serves the hint alone, and it finds no checkout, so
#	CLI-CHECKOUT-4 holds.
sub _split ( $path, $base )
{
	return unless defined $base;

	my $marker = "/$base/";
	my $at     = rindex $path, $marker;
	return if $at < 0;

	my $name = substr $path, $at + length $marker;
	return unless length $name;

	return ( substr( $path, 0, $at ), $name );
}

1;
