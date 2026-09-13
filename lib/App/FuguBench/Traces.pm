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

package App::FuguBench::Traces;

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Cwd            ();
use File::Basename qw(basename);
use File::Spec     ();
use JSON::PP       ();

use Fugu::CLI qw(EXIT_SUCCESS EXIT_ERROR);
use Fugu::Sandbox;

# App::FuguBench::Traces - the traces verb.
#
# The verb measures the Claude Code sessions of one checkout. Claude
# Code keeps one trace directory for each working directory, under
# ~/.claude/projects/. The name of the directory is the absolute path
# of the working directory, and the harness replaces each character
# outside a letter, a digit and a hyphen with a hyphen.
#
# The verb derives that name from the checkout root, it matches the
# trace directories of the checkout, and it prints one line for each
# session in them that holds a request.
#
# The derivation cuts the root at the last .claude/worktrees/ marker,
# because a nested checkout holds the marker more than one time
# (TRACE-NAME-1). Three name forms belong to one checkout: the
# checkout itself, a worktree of it, and a project clone in either of
# them. The match takes the exact forms, so a sibling checkout, such
# as a backup, stays out (TRACE-NAME-2).
#
# The option --root names a trace root in place of the one under the
# home of the operator. The option --name replaces the derived name,
# and the verb then reads no checkout (TRACE-NAME-3).
#
# This verb and the hook verb hold the Claude Code assumptions of the
# program, and every other verb is agent-agnostic (D-10).

# The marker of a worktree path, and the trace root of the harness
# under the home of the operator.
use constant MARKER   => '/.claude/worktrees/';
use constant PROJECTS => '.claude/projects';

# The format of one line. The columns are session, start, and reqs
# (TRACE-COLUMNS-2). The format lives in a variable: on the floor
# perl, printf reads a bareword in that place as a filehandle, and
# the pragma block of the file forbids one.
my $ROW = "%-8s  %-16s  %6s\n";

# The decoder of one record. It takes the bytes of a line, and it
# decodes the UTF-8 itself. An :encoding layer loads the
# PerlIO::encoding extension at the first open, and `stdio rpath`
# gives no promise for the load of a shared object.
my $JSON = JSON::PP->new->utf8;

# App::FuguBench::Traces->command($verb):
#	The entry of the Fugu::CLI table. The module holds one verb,
#	so it ignores the name.
sub command ( $, $ )
{
	return {
		summary => 'measure the sessions of the checkout',
		usage   => '[--root <dir>] [--name <name>]',
		options => {
			'root=s' => 'the trace root, in place of the one'
			    . ' under the home',
			'name=s' => 'the checkout name, in place of the'
			    . ' derived one',
		},
		run => sub ( $app, @argv ) { return _run( $app, @argv ) },
	};
}

# App::FuguBench::Traces->unveil_paths($app):
#	The unveil list of the sandbox row (CLI-SANDBOX-2). The verb
#	opens the trace files itself and runs no child, so its row
#	names each path that the verb reads after the entry, and it
#	names nothing else.
#
#	perl loads a module on an error path, so the list holds the
#	library directories of the interpreter. Each one is optional,
#	because the build of a perl records a directory that the host
#	can omit.
#
#	The trace root is optional too. The verb reports an absent
#	root itself, with the path in the message, and a required
#	entry would die in front of that report.
#
#	The verb resolves the real path of the checkout root after the
#	entry, so the row names the root. The walk to the .toolingrc
#	runs here, in front of the entry, because unveil(2) hides the
#	directories above the root. With --name the verb derives no
#	name, and it reads no checkout.
sub unveil_paths ( $, $app )
{
	my @paths =
	    map { [ $_, 'r', { optional => 1 } ] } Fugu::Sandbox->perl_lib_dirs;

	my $checkout =
	    defined $app->cli->option('name') ? undef : $app->checkout;
	push @paths, [ $checkout->root, 'r' ] if $checkout;

	push @paths, [ _trace_root($app), 'r', { optional => 1 } ];

	return @paths;
}

# _run($app, @argv):
#	The body of the verb. It takes no argument, and an argument
#	is a usage error.
#
#	The rows sort by start time, under one header. A session with
#	no request gets no row, and a name that matches no directory
#	gives the one line that says so (TRACE-COLUMNS-1).
sub _run ( $app, @argv )
{
	return $app->cli->command_usage_error('traces') if @argv;

	my $log  = $app->cli->log;
	my $root = _trace_root($app);
	unless ( -d $root ) {
		$log->error( 'no such trace root: %s', $root );
		return EXIT_ERROR;
	}

	my ( $code, $name ) = _name($app);
	return $code if $code != EXIT_SUCCESS;

	opendir my $dh, $root or do {
		$log->error( 'cannot read %s: %s', $root, $! );
		return EXIT_ERROR;
	};
	my $match = _match($name);
	my @dirs  = sort grep { /$match/ && -d "$root/$_" } readdir $dh;
	closedir $dh;

	my @rows;
	push @rows, _sessions("$root/$_") for @dirs;
	unless (@rows) {
		say "no session of $name";
		return EXIT_SUCCESS;
	}

	printf $ROW, qw(session start reqs);
	for my $row ( sort { $a->{start} cmp $b->{start} } @rows ) {
		printf $ROW, substr( $row->{id}, 0, 8 ),
		    substr( $row->{start}, 0, 16 ), $row->{reqs};
	}

	return EXIT_SUCCESS;
}

# _trace_root($app):
#	The trace root of the run: the --root value, or the directory
#	of the harness under the home of the operator.
sub _trace_root ($app)
{
	my $root = $app->cli->option('root');
	return $root if defined $root;

	return File::Spec->catdir( $ENV{HOME} // q{.}, PROJECTS );
}

# _name($app):
#	The exit code and the trace name, in that order. The code is
#	EXIT_SUCCESS when the name holds a value, and the method
#	reports every failure itself.
#
#	The name is the --name value, or the derivation of
#	TRACE-NAME-1: the real path of the checkout root, cut at the
#	last marker, with each character outside a letter, a digit and
#	a hyphen replaced by a hyphen.
#
#	A worktree holds a .toolingrc of its own, so the walk stops in
#	the worktree and the cut reaches the checkout. CLI-CHECKOUT-4
#	names this cut as the one exception.
sub _name ($app)
{
	my $name = $app->cli->option('name');
	return ( EXIT_SUCCESS, $name ) if defined $name;

	my $checkout = $app->checkout
	    or return Fugu::CLI::EXIT_CONFIG_ERROR();

	my $path = Cwd::abs_path( $checkout->root );
	unless ( defined $path ) {
		$app->cli->log->error( 'cannot resolve %s', $checkout->root );
		return EXIT_ERROR;
	}

	my $at = rindex $path, MARKER;
	$path = substr $path, 0, $at if $at >= 0;

	return ( EXIT_SUCCESS, $path =~ s/[^A-Za-z0-9-]/-/gr );
}

# _match($name):
#	The pattern of the trace directories of one checkout: the
#	checkout itself, each worktree of it, and each project clone
#	in either of them (TRACE-NAME-2). The pattern takes the whole
#	name, so a sibling of the checkout stays out.
sub _match ($name)
{
	my $token = qr{[A-Za-z0-9-]+};

	return qr{
		\A\Q$name\E
		(?:--claude-worktrees-$token)?
		(?:-Projects-$token)?
		\z
	}x;
}

# _sessions($dir):
#	One row for each session of one trace directory. A session
#	with no request never reached the model, so it gets no row
#	(TRACE-COLUMNS-1).
sub _sessions ($dir)
{
	my @rows;
	for my $path ( _jsonl($dir) ) {
		my $row = _tally($path);
		next unless $row->{reqs};

		$row->{id} = basename($path) =~ s/\.jsonl\z//r;
		push @rows, $row;
	}

	return @rows;
}

# _jsonl($dir):
#	The trace files directly in one directory. A directory that no
#	reader can open holds none.
sub _jsonl ($dir)
{
	opendir my $dh, $dir or return ();
	my @names = sort grep { /\.jsonl\z/ && -f "$dir/$_" } readdir $dh;
	closedir $dh;

	return map { "$dir/$_" } @names;
}

# _tally($path):
#	The measures of one trace file: the start time and the
#	request count. A file that no reader can open gives the empty
#	measures, and the caller drops the session.
#
#	The start time comes from the first record that carries one,
#	whatever the type of that record. After that the reader
#	decodes an assistant record only, because a full parse of
#	every record costs minutes over a long history
#	(TRACE-USAGE-2). Every usage block and every tool_use block
#	sits in an assistant record, and every one of those records
#	holds the word `assistant`, so the filter loses no count.
#
#	A line that fails to decode is no record.
sub _tally ($path)
{
	my %row = ( start => q{}, reqs => 0 );
	open my $fh, '<', $path or return \%row;

	my %seen;
	while ( my $line = <$fh> ) {
		my $rec;

		if ( !length $row{start} ) {
			$rec = eval { $JSON->decode($line) };
			$row{start} = $rec->{timestamp} // q{}
			    if ref $rec eq 'HASH';
		}

		$rec = eval { $JSON->decode($line) }
		    if !defined $rec && index( $line, 'assistant' ) >= 0;
		next
		    unless ref $rec eq 'HASH'
		    && ( $rec->{type} // q{} ) eq 'assistant';

		# One request writes one record for each content block
		# (TRACE-USAGE-1). An old trace carries no requestId,
		# and its records then count one by one, which is the
		# safe direction.
		my $req = $rec->{requestId} // $rec->{uuid} // q{};
		$row{reqs}++ unless $seen{$req}++;
	}
	close $fh;

	return \%row;
}

1;
