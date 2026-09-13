#!/usr/bin/env perl
# ex:ts=8 sw=4:
# The port of the Workspace test t/ci/traces.t (CLI-CONFORMANCE-1).
# It tests the trace name, the directory match, and the session rows
# of the traces verb (TRACE-NAME, TRACE-COLUMNS, TRACE-USAGE).
#
# The test makes a fixture checkout and a fixture trace root in one
# temp tree, and it runs the verb with -C, --root and --name. The
# trace root holds the checkout, one worktree of it, one project
# clone in it, and one sibling checkout that must stay out. The
# checkout holds the main session and one session with no request.
#
# The last test runs the verb with --root alone, against a -C
# directory that holds the marker two times, which reaches the name
# derivation.
#
# The checkout of the fixture is the -C directory, so no assertion
# holds an operator path. No test reads the operator home, and no
# test writes outside its temp tree.

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Test::More;
use Cwd        qw(abs_path);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin    qw($RealBin);
use JSON::PP   ();

my $lib     = "$RealBin/../../lib";
my $program = "$RealBin/../../bin/fugubench";
my $json    = JSON::PP->new->canonical;

# _write($path, $text):
#	Write one file, and make its parent directories.
sub _write ( $path, $text )
{
	make_path( $path =~ s{/[^/]+\z}{}r );
	open my $fh, '>', $path or die "write $path: $!";
	print {$fh} $text;
	close $fh;
}

# _tool($name, %input):
#	One tool_use content block.
sub _tool ( $name, %input )
{
	return {
		type  => 'tool_use',
		id    => "toolu_$name",
		name  => $name,
		input => {%input},
	};
}

# _record($req, $context, $out, @blocks):
#	One assistant record. $context holds the three input counts,
#	which the verb adds together.
sub _record ( $req, $context, $out, @blocks )
{
	return $json->encode( {
			type      => 'assistant',
			timestamp => '2026-09-09T10:00:00.000Z',
			requestId => $req,
			message   => {
				role  => 'assistant',
				usage => {
					input_tokens => $context->[0],
					cache_creation_input_tokens =>
					    $context->[1],
					cache_read_input_tokens =>
					    $context->[2],
					output_tokens => $out,
				},
				content => [@blocks],
			},
		} ) . "\n";
}

# _session($id):
#	A one-request trace, as the smallest session that gets a row.
sub _session ($id)
{
	return _record( "req_$id", [ 1, 2, 3 ],
		4, { type => 'text', text => 'x' } );
}

# _traces($checkout, $root, $name):
#	Run the verb against the fixture root, with the fixture
#	checkout as the -C directory. The exit code and the output.
sub _traces ( $checkout, $root, $name )
{
	my $cmd = qq("$^X" "-I$lib" "$program" -C "$checkout" traces);
	my $out = qx($cmd --root "$root" --name "$name" 2>&1);

	return ( $? >> 8, $out );
}

my $tree = tempdir( CLEANUP => 1 );
my $cwd  = "$tree/checkout";
my $root = "$tree/traces";
my $main = "$root/fixture";
my $id   = '11111111-1111-1111-1111-111111111111';

# The checkout walk of the program stops at a .toolingrc, so no run
# of the test reads the operator home (CLI-CHECKOUT-2).
_write( "$cwd/.toolingrc", q{} );

# The path of the fixture checkout. The edits column takes a file
# inside this path only, so the scratch case builds its path from it.
my $checkout = abs_path($cwd);

# The fixer of round 1. Its description holds the word panel, and its
# type names another role, so neither the panel count nor rev-peak
# takes it. _tool derives the identifier from the tool name, so the
# fixer needs an identifier of its own, apart from the panel launch.
my $fixer = _tool(
	'Agent',
	subagent_type => 'fixer',
	description   => 'Panel round 1 fixer'
);
$fixer->{id} = 'toolu_fixer';

# The main session: one leading record that carries the start time,
# then three requests. Request A writes three records, because one
# record carries one content block. Its first two records carry a
# partial count, and its last record carries the full count, which
# holds the peak of the file. Its Edit comes before the panel launch,
# so no count takes it. Request B holds two edits after the launch,
# and the launch of the fixer. Request C writes two files under
# scratch/, one path relative and one path absolute inside the
# checkout, which no count takes.
_write(
	"$main/$id.jsonl",
	$json->encode(
		{ type => 'user', timestamp => '2026-09-09T09:59:00.000Z' } )
	    . "\n"
	    . _record( 'req_a', [ 1, 20, 300 ],
		5, { type => 'text', text => 'x' } )
	    . _record( 'req_a', [ 2, 30, 400 ], 10, _tool('Edit') )
	    . _record( 'req_a', [ 30, 300, 3000 ],
		70, _tool( 'Agent', description => 'Panel review member 1' ) )
	    . _record(
		'req_b',        [ 20, 200, 2000 ],
		60,             _tool('Edit'),
		_tool('Write'), $fixer
	    )
	    . _record(
		'req_c',
		[ 5, 50, 500 ],
		10,
		_tool( 'Write', file_path => 'scratch/review/ledger.md' ),
		_tool(
			'NotebookEdit',
			notebook_path => "$checkout/scratch/note.ipynb"
		) ) );

# A session that holds records but no assistant record never reached
# the model, so it gets no row (TRACE-COLUMNS-1).
my $quiet = $json->encode(
	{ type => 'user', timestamp => '2026-09-09T10:01:00.000Z' } );
_write( "$main/77777777-7777.jsonl", "$quiet\n$quiet\n" );

# One worktree of the checkout, one project clone in it, and one
# sibling checkout that the match must reject.
_write( "$root/fixture--claude-worktrees-w1/22222222-2222.jsonl",
	_session('w') );
_write( "$root/fixture-backup/33333333-3333.jsonl",           _session('b') );
_write( "$root/fixture-Projects-Tooling/44444444-4444.jsonl", _session('p') );

my ( $code, $out ) = _traces( $cwd, $root, 'fixture' );
is( $code, 0, 'traces exits zero' );

my ($row) = grep { /^11111111\b/ } split /\n/, $out;
ok( $row, 'the main session gets a row' ) or diag $out;
my @field = split q{ }, $row // q{};

is( $field[1], '2026-09-09T09:59', 'the start time is the first record' );
is( $field[2], 3,                  'the record count is a request count' );

like( $out, qr/^22222222/m, 'a worktree of the checkout joins' );
like( $out, qr/^44444444/m, 'a project clone joins' );
unlike( $out, qr/^33333333/m, 'a sibling checkout stays out' );

unlike( $out, qr/^77777777/m, 'a session with no request gets no row' );

my ( $none_code, $none_out ) = _traces( $cwd, $root, 'absent' );
is( $none_code, 0, 'a name with no trace directory exits zero' );
like( $none_out, qr/^no session of absent$/m, 'and it reports none' );

# Without --name, the verb derives the name from the checkout root,
# cut at the last .claude/worktrees/ marker (TRACE-NAME-1). The -C
# directory sits under two markers, and it holds a .toolingrc of its
# own, so it is the checkout root. The last marker names the inner
# checkout, and the first one names the outer checkout, whose trace
# directory must stay out.
my $nest = tempdir( CLEANUP => 1 );
my $deep = "$nest/.claude/worktrees/a/.claude/worktrees/b";
_write( "$deep/.toolingrc", q{} );

my $outer = abs_path($nest)                       =~ s/[^A-Za-z0-9-]/-/gr;
my $inner = abs_path("$nest/.claude/worktrees/a") =~ s/[^A-Za-z0-9-]/-/gr;
_write( "$nest/traces/$inner/55555555-5555.jsonl", _session('n') );
_write( "$nest/traces/$outer/66666666-6666.jsonl", _session('o') );

my $deep_cmd = qq("$^X" "-I$lib" "$program" -C "$deep" traces);
my $deep_out = qx($deep_cmd --root "$nest/traces" 2>&1);
is( $? >> 8, 0, 'the derived name exits zero' );
like( $deep_out, qr/^55555555/m, 'the derivation cuts at the last marker' )
    or diag $deep_out;
unlike( $deep_out, qr/^66666666/m, 'and the outer checkout stays out' );

done_testing();
