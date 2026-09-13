#!/usr/bin/env perl
# ex:ts=8 sw=4:
# The shim verb, the install verb, and the install script (DIST-SHIM,
# DIST-INSTALL, DIST-VERSION, CLI-SANDBOX).
#
# The shim pins one release, so a checkout prints none. The file
# therefore builds one pack with a version that no release holds, and
# the shim cases run that pack. The build runs at the repository
# root, as t/fugubench/pack.t does. That build writes install.sh
# beside the pack, and one case runs that script.
#
# A stub downloader on a temporary PATH serves the pack, so no case
# reaches the network. Each case sets HOME to its own temporary tree,
# reads no operator home, and writes nowhere else. The pack build
# carries PERL5LIB, because scripts/dist and scripts/pack load the
# installed Fugu. No other child carries it: the packed file must
# need no installed Fugu.

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Test::More;
use Cwd            ();
use Digest::SHA    ();
use File::Basename ();
use File::Spec     ();
use File::Temp     qw(tempdir);
use FindBin        qw($RealBin);
use lib "$RealBin/../../lib";

use Fugu;
use Fugu::Log;
use Fugu::Process;
use Fugu::Sandbox;

use App::FuguBench;
use App::FuguBench::Checkout;

my $root    = "$RealBin/../..";
my $program = "$root/bin/fugubench";

# The version of the pack under test. No release holds it, so no
# stamp of a checkout passes a case by accident.
my $VERSION = '9.9.9';

# The directory of the running perl. The packed file starts with
# `#!/usr/bin/env perl`, so the PATH of a shim run must name a perl.
my $PERLDIR = File::Basename::dirname( Cwd::abs_path($^X) // $^X );

# The stub downloader. It serves one file, and it records each call,
# so a case reads how many times the shim reached for the network.
my $STUB = <<'STUB';
#!/bin/sh
echo "curl $*" >> '%s'
out=
while [ $# -gt 0 ]; do
	case $1 in
	-o)	out=$2; shift 2 ;;
	*)	shift ;;
	esac
done
cat '%s' > "$out"
STUB

# _read($path):
#	The whole text of one file.
sub _read ($path)
{
	open my $fh, '<', $path or do {
		fail("$path is readable");
		return q{};
	};
	binmode $fh;
	local $/ = undef;
	my $text = <$fh>;
	close $fh;

	return $text;
}

# _write($path, $text):
#	Write one file of a temporary tree.
sub _write ( $path, $text )
{
	open my $fh, '>', $path or die "cannot write $path: $!\n";
	print {$fh} $text;
	close $fh or die "cannot close $path: $!\n";

	return $path;
}

# _sha256($path):
#	The sha256 digest of one file, in lower-case hex.
sub _sha256 ($path)
{
	open my $fh, '<', $path or die "cannot read $path: $!\n";
	binmode $fh;
	my $digest = Digest::SHA->new(256)->addfile($fh)->hexdigest;
	close $fh;

	return $digest;
}

# _entries($dir):
#	The names in one directory, sorted, without the two dots. An
#	absent directory gives the empty list.
sub _entries ($dir)
{
	opendir my $dh, $dir or return ();
	my @names = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
	closedir $dh;

	return @names;
}

# _mode($path):
#	The permission bits of one file.
sub _mode ($path)
{
	return ( stat $path )[2] & 07777;
}

# _env(%extra):
#	The environment of a child. The child holds the named
#	variables and nothing else, so no variable of the operator
#	reaches it.
sub _env (%extra)
{
	return { PATH => $ENV{PATH} // '/usr/bin:/bin', %extra };
}

# _pack():
#	Build one pack in a temporary tree, and return the path of the
#	packed file and the path of the install script beside it.
sub _pack ()
{
	my $dir = tempdir( CLEANUP => 1 );
	my $r   = Fugu::Process->run(
		cmd => [
			$^X, 'scripts/pack', '--version', $VERSION,
			'--out', $dir
		],
		cwd => $root,
		env => _env(
			HOME => $dir,
			defined $ENV{PERL5LIB}
			? ( PERL5LIB => $ENV{PERL5LIB} )
			: ()
		),
	);
	die "cannot run scripts/pack: $r->{error}\n" if defined $r->{error};
	die "scripts/pack exited $r->{exit_code}: $r->{stderr}\n"
	    unless $r->{success};

	return map { File::Spec->catfile( $dir, $_ ) }
	    qw(fugubench install.sh);
}

# _run($home, $path, @argv):
#	Run one program as a child, with HOME and the current
#	directory in one temporary tree.
sub _run ( $home, $path, @argv )
{
	my $r = Fugu::Process->run(
		cmd => [ $path, @argv ],
		cwd => $home,
		env => _env( HOME => $home ),
	);
	die "cannot run $path: $r->{error}\n" if defined $r->{error};

	return $r;
}

# _stamped( $version, @argv ):
#	Run the program as a child with one stamped version. The dist
#	build stamps `our $VERSION` into every package, and a
#	checkout carries no stamp, so the child writes the variable
#	that the stamp writes.
sub _stamped ( $version, @argv )
{
	my $home = tempdir( CLEANUP => 1 );
	my $r    = Fugu::Process->run(
		cmd => [
			$^X, "-I$root/lib", '-e',
			'use App::FuguBench;'
			    . ' $App::FuguBench::VERSION = shift;'
			    . ' exit App::FuguBench->new->run(@ARGV)',
			$version, @argv
		],
		cwd => $home,
		env => _env( HOME => $home ),
	);
	die "cannot run the stamped program: $r->{error}\n"
	    if defined $r->{error};

	return $r;
}

# _shell($home, $bin, $shim, %extra):
#	Run one shim with a PATH of its own. $bin is the directory of
#	the stub downloader, and %extra adds a variable to the
#	environment of the child.
sub _shell ( $home, $bin, $shim, %extra )
{
	my $r = Fugu::Process->run(
		cmd => [ '/bin/sh', $shim, @{ delete $extra{argv} // [] } ],
		cwd => $home,
		env => {
			PATH => "$bin:$PERLDIR:/usr/bin:/bin:/sbin",
			HOME => $home,
			%extra
		},
	);
	die "cannot run /bin/sh: $r->{error}\n" if defined $r->{error};

	return $r;
}

# _entered(@argv):
#	Run the program in process, with the two sandbox calls
#	replaced. The helper reports the exit code, the promise sets
#	of the run, the unveil entries, and the result of the verb.
#
#	It reports each path that exists at the call as well. A
#	required entry of an absent path stops the unveil, so a row
#	that makes a directory must make it before the call.
#
#	The result of the verb goes to a string, and the logger is
#	quiet, so neither stream joins the test output.
sub _entered (@argv)
{
	my ( @promises, @paths, %present );
	my $out = q{};
	my $code;

	my $log = Fugu::Log->default;
	Fugu::Log->set_default( Fugu::Log->new( mode => 'quiet' ) );
	{
		no warnings 'redefine';
		local *Fugu::Sandbox::pledge = sub ( $, %args ) {
			push @promises, $args{promises};
			return 1;
		};
		local *Fugu::Sandbox::unveil = sub ( $, %args ) {
			for my $entry ( @{ $args{paths} } ) {
				push @paths, $entry;
				$present{ $entry->[0] } = -e $entry->[0] ? 1 : 0;
			}
			return 1;
		};

		open my $fh, '>', \$out or die "capture: $!";
		my $old = select $fh;
		$code = App::FuguBench->new->run(@argv);
		select $old;
		close $fh;
	}
	Fugu::Log->set_default($log);

	return {
		code     => $code,
		promises => \@promises,
		paths    => \@paths,
		present  => \%present,
		out      => $out,
	};
}

my ( $packed, $script ) = _pack();
my $digest = _sha256($packed);
my $line   = sprintf "fugubench %s (Fugu %s)\n", $VERSION, Fugu->VERSION;

# The shim text of the pack. Every shim case reads it.
my $text;
subtest 'the shim of a release' => sub {
	my $home = tempdir( CLEANUP => 1 );
	my $r    = _run( $home, $packed, 'shim' );
	is( $r->{exit_code}, 0,   'shim exits 0' );
	is( $r->{stderr},    q{}, 'shim writes nothing to standard error' );
	$text = $r->{stdout};

	my @lines = split /^/, $text;
	ok( @lines <= 60, 'the shim fits in 60 lines' )
	    or diag scalar @lines;

	# The URL of the version that printed it, and the digest of
	# the file that printed it (DIST-SHIM-1)
	like(
		$text,
		qr{^url=https://github[.]com/FuguBSD/FuguBench/releases/download/v\Q$VERSION\E/fugubench$}m,
		'the shim holds the URL of the release'
	);
	like( $text, qr/^want=\Q$digest\E$/m,
		'the shim holds the digest of the packed file' );

	my $shim = _write( "$home/fugubench.sh", $text );
	my $n = Fugu::Process->run(
		cmd => [ '/bin/sh', '-n', $shim ],
		env => _env( HOME => $home ),
	);
	is( $n->{exit_code}, 0, 'sh -n accepts the shim' )
	    or diag $n->{stderr};
};

subtest 'a file that no release stamped pins nothing' => sub {

	# A checkout carries no stamp at all, and a build of a tree
	# with no tag carries 0.0.0. No release holds either one.
	is( App::FuguBench->VERSION, undef, 'the checkout carries no stamp' );

	my $home = tempdir( CLEANUP => 1 );
	my $r = _run( $home, $^X, "-I$root/lib", $program, 'shim' );
	is( $r->{exit_code}, 1,   'the checkout shim exits 1' );
	is( $r->{stdout},    q{}, 'and it prints no shim' );
	like(
		$r->{stderr}, qr/no release stamped this file/,
		'and the message names the reason'
	);

	my $s = _stamped( '0.0.0', 'shim' );
	is( $s->{exit_code}, 1,   'a build of 0.0.0 exits 1 too' );
	is( $s->{stdout},    q{}, 'and it prints no shim' );
	like(
		$s->{stderr}, qr/no release stamped this file/,
		'and it names the same reason'
	);
};

subtest 'the shim fetches, verifies, caches, and runs' => sub {
	my $home = tempdir( CLEANUP => 1 );
	my $bin  = tempdir( CLEANUP => 1 );
	my $log  = "$bin/calls";
	_write( "$bin/curl", sprintf $STUB, $log, $packed );
	chmod 0755, "$bin/curl" or die "chmod: $!";

	my $shim  = _write( "$home/fugubench.sh", $text );
	my $cache = "$home/.cache/fugubench/$VERSION";

	my $r = _shell( $home, $bin, $shim, argv => ['version'] );
	is( $r->{exit_code}, 0,     'the first run exits 0' );
	is( $r->{stdout},    $line, 'and the argument reaches the program' );
	ok( -f $log, 'and the shim ran the downloader' );

	my $file = "$cache/fugubench";
	ok( -f $file, 'the shim caches the packed file' );
	is( _mode($file), 0755, 'and the cached file holds mode 755' );
	is( _sha256($file), $digest, 'and it holds the bytes of the pack' );

	# The second run reads the cache, so the downloader records
	# no second call (DIST-SHIM-3).
	my $again = _shell( $home, $bin, $shim, argv => ['version'] );
	is( $again->{exit_code}, 0,     'the second run exits 0' );
	is( $again->{stdout},    $line, 'and it prints the same line' );
	my @calls = split /^/, _read($log);
	is( scalar @calls, 1, 'and it reaches no downloader' );

	# The shim exits with the code of the program, and an unknown
	# verb is a usage error (DIST-SHIM-5, CLI-PROGRAM-3).
	my $bad = _shell( $home, $bin, $shim, argv => ['nosuchverb'] );
	is( $bad->{exit_code}, 2, 'the shim exits with the code of the program' );
	like(
		$bad->{stderr}, qr/^usage: fugubench /m,
		'and the usage of the program reaches standard error'
	);
};

subtest 'a download that fails the digest stops the shim' => sub {
	my $home  = tempdir( CLEANUP => 1 );
	my $bin   = tempdir( CLEANUP => 1 );
	my $log   = "$bin/calls";
	my $other = _write( "$home/other", "not the packed file\n" );
	my $wrong = _sha256($other);
	_write( "$bin/curl", sprintf $STUB, $log, $other );
	chmod 0755, "$bin/curl" or die "chmod: $!";

	my $shim = _write( "$home/fugubench.sh", $text );
	my $r = _shell( $home, $bin, $shim, argv => ['version'] );
	isnt( $r->{exit_code}, 0,   'the shim exits non-zero' );
	is( $r->{stdout},      q{}, 'and no program runs' );
	like( $r->{stderr}, qr/\Qwant $digest\E/,
		'and the message holds the expected digest' );
	like( $r->{stderr}, qr/\Qgot $wrong\E/,
		'and it holds the computed digest' );

	is_deeply( [ _entries("$home/.cache/fugubench/$VERSION") ],
		[], 'the shim deletes the download' );
};

subtest 'FUGUBENCH replaces the download' => sub {
	my $home = tempdir( CLEANUP => 1 );
	my $bin  = tempdir( CLEANUP => 1 );
	my $log  = "$bin/calls";
	_write( "$bin/curl", sprintf $STUB, $log, $packed );
	chmod 0755, "$bin/curl" or die "chmod: $!";

	my $shim = _write( "$home/fugubench.sh", $text );
	my $r = _shell( $home, $bin, $shim,
		argv => ['version'], FUGUBENCH => $packed );
	is( $r->{exit_code}, 0,     'the shim exits 0' );
	is( $r->{stdout},    $line, 'and it runs the named file' );
	ok( !-e $log, 'and it reaches no downloader' );
	ok( !-e "$home/.cache", 'and it writes no cache' );
};

subtest 'the shim names the downloaders that it wants' => sub {
	my $home = tempdir( CLEANUP => 1 );
	my $bin  = tempdir( CLEANUP => 1 );

	# The PATH holds one empty directory, so the shim finds no
	# downloader at all (DIST-SHIM-7).
	my $shim = _write( "$home/fugubench.sh", $text );
	my $r    = Fugu::Process->run(
		cmd => [ '/bin/sh', $shim, 'version' ],
		cwd => $home,
		env => { PATH => $bin, HOME => $home },
	);
	die "cannot run /bin/sh: $r->{error}\n" if defined $r->{error};

	isnt( $r->{exit_code}, 0, 'the shim exits non-zero' );
	like( $r->{stderr}, qr/curl/,  'the message names curl' );
	like( $r->{stderr}, qr/wget/,  'and wget' );
	like( $r->{stderr}, qr/\bftp/, 'and ftp' );
	ok( !-e "$home/.cache", 'and the shim makes no cache directory' );
};

subtest 'install copies the running file' => sub {
	my $home = tempdir( CLEANUP => 1 );
	ok(
		!defined App::FuguBench::Checkout->new( start => $home ),
		'the temporary tree sits under no checkout'
	);

	my $dir    = "$home/.local/bin";
	my $target = "$dir/fugubench";

	# The umask of the operator reaches the open of the write, and
	# DIST-INSTALL-2 wants the mode of the file.
	my $old = umask 0077;
	my $r   = _run( $home, $packed, 'install' );
	umask $old;

	is( $r->{exit_code},  0,           'install exits 0' );
	is( $r->{stdout},     "$target\n", 'and it prints the path' );
	is( _sha256($target), $digest,     'and the copy holds the bytes' );
	is( _mode($target),   0755,        'and it holds mode 755' );

	# The verb reads no checkout, so no walk reports one
	# (CLI-CHECKOUT-5).
	unlike( $r->{stderr}, qr/toolingrc/,
		'and it reports no configuration error' );
	like(
		$r->{stderr}, qr/no PATH entry names \Q$dir\E/,
		'and it hints when no PATH entry names the directory'
	);

	# The second run replaces the file, and the hint stays away
	# when the directory sits on PATH (DIST-INSTALL-2).
	my $p = Fugu::Process->run(
		cmd => [ $packed, 'install' ],
		cwd => $home,
		env => { PATH => "$dir:/usr/bin:/bin", HOME => $home },
	);
	die "cannot run $packed: $p->{error}\n" if defined $p->{error};
	is( $p->{exit_code}, 0,           'the second install exits 0' );
	is( $p->{stdout},    "$target\n", 'and it prints the path again' );
	is( $p->{stderr},    q{},         'and it prints no hint' );
	is( _mode($target),  0755,        'and the mode holds' );
};

subtest 'the install script fetches the pack and installs it' => sub {
	my $home = tempdir( CLEANUP => 1 );
	my $bin  = tempdir( CLEANUP => 1 );
	my $log  = "$bin/calls";
	_write( "$bin/curl", sprintf $STUB, $log, $packed );
	chmod 0755, "$bin/curl" or die "chmod: $!";

	my $n = Fugu::Process->run(
		cmd => [ '/bin/sh', '-n', $script ],
		env => _env( HOME => $home ),
	);
	is( $n->{exit_code}, 0, 'sh -n accepts the install script' )
	    or diag $n->{stderr};

	# The script is the shim with one argument list, so it fetches
	# and verifies as the shim does, and then it runs the install
	# verb of the packed file (DIST-INSTALL-1).
	my $r      = _shell( $home, $bin, $script );
	my $target = "$home/.local/bin/fugubench";
	is( $r->{exit_code}, 0, 'the install script exits 0' )
	    or diag $r->{stderr};
	is( $r->{stdout},     "$target\n", 'and it prints the installed path' );
	is( _sha256($target), $digest, 'and the copy holds the bytes of the pack' );
	is( _mode($target),   0755,    'and the copy holds mode 755' );

	ok( -f $log, 'the script reaches the downloader' );
	ok(
		-f "$home/.cache/fugubench/$VERSION/fugubench",
		'and the fetch passes through the shim cache'
	);
};

subtest 'the two sandbox rows' => sub {
	my @lib = map { [ $_, 'r', { optional => 1 } ] }
	    Fugu::Sandbox->perl_lib_dirs;

	# The row runs in front of the verb, and the checkout that
	# runs this test carries no stamp, so the verb returns 1.
	my $s = _entered('shim');
	is( $s->{code}, 1, 'shim exits 1 in a checkout' );
	is_deeply( $s->{promises}, ['stdio rpath'],
		'the shim row pledges stdio rpath, and no write promise' );
	is_deeply(
		$s->{paths},
		[ @lib, [ $RealBin, 'r' ] ],
		'and it unveils the library directories and the running file'
	);

	# The install row adds the install directory, and it makes
	# that directory, because unveil(2) hides what the list
	# leaves out (CLI-SANDBOX-2).
	my $home = tempdir( CLEANUP => 1 );
	local $ENV{HOME} = $home;
	my $dir = "$home/.local/bin";

	my $i = _entered('install');
	is( $i->{code}, 0, 'install exits 0' );
	is_deeply(
		$i->{promises},
		['stdio rpath wpath cpath fattr'],
		'the install row pledges the write promises'
	);
	is_deeply(
		$i->{paths},
		[ @lib, [ $RealBin, 'r' ], [ $dir, 'rwc' ] ],
		'and it unveils the install directory beside them'
	);
	is( $i->{present}{$dir}, 1, 'the row makes it before the call' );

	# The verb copies the running file, and this run is the test
	# itself.
	is( $i->{out}, "$dir/fugubench\n", 'the verb prints the path' );
	is(
		_sha256("$dir/fugubench"),
		_sha256( Cwd::abs_path($0) ),
		'and it copies the running file'
	);
};

done_testing();
