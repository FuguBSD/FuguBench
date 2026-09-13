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

package App::FuguBench;

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Cwd          ();
use Getopt::Long ();

use Fugu::CLI;
use Fugu::Process;
use Fugu::Sandbox;

use App::FuguBench::Checkout;
use App::FuguBench::Version;

# App::FuguBench - the dispatcher of the fugubench program.
#
# Every verb shares one dispatcher, one checkout discovery, one
# sandbox entry, and one channel discipline. Fugu::CLI parses the
# global options, finds the verb, parses the options of the verb, and
# calls it. Its exit codes are the codes of the program.
#
# Standard output carries the result line of a verb, and nothing
# else. Every diagnostic goes to the logger, which writes to standard
# error, because a hook reads standard output.
#
# The namespace is an application, not a library. It uses Fugu:: and
# core Perl, and it never uses another App:: namespace.

# The verb table. Each entry names a verb and the module that holds
# it. The module returns the entry of the Fugu::CLI table from its
# command class method.
my @VERBS = ( [ 'version', 'App::FuguBench::Version' ], );

# The sandbox row of each verb (CLI-SANDBOX). A row names the pledge
# promises of the verb, and it names nothing else.
#
# `version` opens no file, so its row holds `stdio` alone, and
# `stdio` denies open(2). The first verb that opens a file adds the
# unveil of CLI-SANDBOX-2, and the paths of its row.
my %SANDBOX = ( version => { promises => 'stdio' }, );

# The global options, in the form of Fugu::CLI. new gives the table
# to the dispatcher, and run reads the same table to find the verb.
my %OPTIONS = (
	'C=s'     => 'the directory that a verb reads as its checkout root',
	'verbose' => 'trace each command on standard error',
);

# App::FuguBench->new:
#	Build the dispatcher over Fugu::CLI. The global options are
#	-C <dir> and --verbose.
sub new ($class)
{
	my $self = bless {
		cli      => undef,
		checkout => undef,
		error    => undef,
	}, $class;

	$self->{cli} = Fugu::CLI->new(
		name  => 'fugubench',
		usage => '[-C <dir>] [--verbose] <verb> [options] [arguments]',
		options  => \%OPTIONS,
		commands => $self->_commands,
	);

	return $self;
}

# $self->_commands:
#	The Fugu::CLI command table. Each entry comes from the verb
#	module, and the wrapper enters the sandbox row of the verb
#	before the body runs.
sub _commands ($self)
{
	my %table;
	for my $verb (@VERBS) {
		my ( $name, $module ) = @$verb;
		die "$name has no sandbox row" unless $SANDBOX{$name};

		my $entry = $module->command($name);
		my $body  = $entry->{run};
		$entry->{run} = sub ( $, @argv ) {
			$self->_sandbox($name);
			return $body->( $self, @argv );
		};
		$table{$name} = $entry;
	}

	return \%table;
}

# $self->_sandbox($verb):
#	Enter the sandbox row of one verb. The method pledges the
#	promises of the row. On a platform other than OpenBSD the
#	call changes nothing.
sub _sandbox ( $self, $verb )
{
	my $row = $SANDBOX{$verb};

	Fugu::Sandbox->pledge( promises => $row->{promises} );

	return $self;
}

# $self->run(@argv):
#	Parse, enter the sandbox, dispatch, and return the exit code.
#
#	A command line with no verb is a usage error, and a global
#	option in front of it changes nothing. Fugu::CLI prints the
#	help for such a line and returns success, and CLI-PROGRAM-3
#	wants the usage on standard error with exit 2. So the method
#	looks for the verb first, on a copy of the arguments and with
#	the parse rules of Fugu::CLI.
#
#	The copy declares the global options alone. It passes an
#	unknown option, a missing option value, and a request for the
#	help through, so each one stays in the array and the guard
#	passes. Fugu::CLI meets them again, and it answers or reports
#	each one once.
sub run ( $self, @argv )
{
	my @rest   = @argv;
	my $parser = Getopt::Long::Parser->new;
	$parser->configure(
		qw(require_order bundling no_ignore_case pass_through));

	my %values;
	$parser->getoptionsfromarray( \@rest, \%values, keys %OPTIONS );

	# The parse passes `--` through. It ends the options, and it
	# is no verb and no request for the help.
	shift @rest if @rest && $rest[0] eq q{--};

	return $self->{cli}->usage_error unless @rest;

	return $self->{cli}->run(@argv);
}

# $self->cli:
#	The Fugu::CLI dispatcher. A verb body reads its options
#	through $app->cli->option and reports through
#	$app->cli->log.
sub cli ($self)
{
	return $self->{cli};
}

# $self->error:
#	The reason of the last failure of command(), or undef.
sub error ($self)
{
	return $self->{error};
}

# $self->checkout($checkout):
#	The checkout of the run. Without an argument the walk runs on
#	the first call, from the -C value or from the current
#	directory. A verb that reads no checkout never starts it, so
#	the program runs in a home with no .toolingrc.
#
#	The method returns undef when no .toolingrc sits above the
#	start, and it names the start directory in the log. The verb
#	then returns EXIT_CONFIG_ERROR.
#
#	With an argument the method sets the checkout, for a verb that
#	reads its start from a payload.
sub checkout ( $self, $checkout = undef )
{
	if ( defined $checkout ) {
		$self->{checkout} = $checkout;
		return $checkout;
	}
	return $self->{checkout} if defined $self->{checkout};

	my $start = $self->{cli}->option('C') // Cwd::getcwd();
	$self->{checkout} = App::FuguBench::Checkout->new( start => $start );
	$self->{cli}->log->error( 'no .toolingrc above %s', $start )
	    unless defined $self->{checkout};

	return $self->{checkout};
}

# $self->command(\@cmd, %args):
#	Run one child command through Fugu::Process->run, as an
#	argument list and never through a shell. The remaining
#	arguments reach Fugu::Process->run, so a caller names cwd,
#	stdin, env or timeout there.
#
#	The method writes the command line to standard error under
#	--verbose, before the child runs. It writes the captured
#	standard error of the child to standard error, in full.
#
#	It returns the captured standard output, and undef with the
#	reason in error(). A child that writes nothing gives the empty
#	string, so a caller tests the return value with defined.
sub command ( $self, $cmd, %args )
{
	my $log = $self->{cli}->log;
	$self->{error} = undef;

	$log->info( 'run: %s', join q{ }, @$cmd )
	    if $self->{cli}->option('verbose');

	my $result = Fugu::Process->run( cmd => $cmd, %args );
	if ( defined $result->{error} ) {
		$self->{error} = $result->{error};
		return;
	}

	print STDERR $result->{stderr} if length $result->{stderr};

	unless ( $result->{success} ) {
		$self->{error} =
		    $result->{timed_out}
		    ? "$cmd->[0] timed out"
		    : "$cmd->[0] exited $result->{exit_code}";
		return;
	}

	return $result->{stdout};
}

1;
