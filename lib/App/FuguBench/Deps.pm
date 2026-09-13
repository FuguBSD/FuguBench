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

package App::FuguBench::Deps;

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use File::Spec ();
use File::Temp ();
use POSIX      qw(uname);

use Fugu::CLI qw(EXIT_SUCCESS EXIT_ERROR);
use Fugu::File;
use Fugu::Process;
use Fugu::Signify;

# App::FuguBench::Deps - the deps verb.
#
# The verb reads the external tools, the Perl distributions, the CPAN
# modules, and the prebuilt binaries that deps/<OS>.txt names, and it
# prints the command of each one. The design comes from the synced
# scripts/deps, and the trace of --dry-run is the oracle of
# CLI-CONFORMANCE-2.
#
# The verb reads deps/<OS>.txt relative to the start directory, and
# it walks up to no checkout (CLI-CHECKOUT-5). A guest runs
# `make deps` out of an extracted tarball, and that tree holds no
# .toolingrc.
#
# The verb validates every line of the manifest before the first
# install, and not the lines of the wanted environment alone
# (DEPS-MANIFEST-3). A bad line of another environment would
# otherwise stay invisible until someone installs that environment.
#
# The install of an entry needs the downloader, the digest check, and
# the installers. The program holds none of them, so the verb takes
# --dry-run alone, and it prints the trace of each command that it
# would run.

# The environments of a manifest line (DEPS-MANIFEST-2).
use constant ENVIRONMENTS => qw(tool runtime test develop);

# The types of a manifest line, in the install order of
# DEPS-MANIFEST-4. A package can give the toolchain that a dist build
# needs, and a dist can give a module that the cpan list builds on. A
# binary depends on nothing here.
use constant TYPES => qw(pkg dist cpan bin);

# The standalone cpanm script. It is the one download that no
# manifest names, so it carries no check (DEPS-INSTALL-4).
use constant CPANM_URL => 'https://cpanmin.us';

# The asset spellings of one system name and one machine name, in
# preference order (DEPS-ALIAS-2). GitHub answers an asset path in
# any letter case, so macOS also covers macos. Two spellings of one
# name would name one download twice, and raise a false ambiguity.
my %OS_ALIAS = (
	Darwin  => [qw(darwin macOS osx)],
	Linux   => [qw(linux)],
	OpenBSD => [qw(openbsd)],
);

my %ARCH_ALIAS = (
	x86_64  => [qw(amd64 x64 x86_64)],
	amd64   => [qw(amd64 x64 x86_64)],
	aarch64 => [qw(arm64 aarch64)],
	arm64   => [qw(arm64 aarch64)],
);

# The shape of a word that becomes a file name (DEPS-INSTALL-8): the
# command name of a bin entry, and the value of --os and --arch. The
# first character is a letter or a digit, so the word is neither an
# option of tar and unzip, nor a parent segment of a path.
my $FILE_NAME = qr{\A[A-Za-z0-9][A-Za-z0-9._-]*\z};

# App::FuguBench::Deps->command($verb):
#	The entry of the Fugu::CLI table. The module holds one verb,
#	so it ignores the name.
sub command ( $, $ )
{
	return {
		summary => 'install one dependency environment',
		usage   => '--dry-run [--os <name>] [--arch <name>]'
		    . ' <tool|runtime|test|develop>',
		options => {
			'dry-run' => 'print each command, and run none of them',
			'os=s'    => 'the system name, in place of uname',
			'arch=s'  => 'the machine name, in place of uname',
		},
		run => sub ( $app, @argv ) { return _run( $app, @argv ) },
	};
}

# _run($app, @argv):
#	The body of the verb. The argument is one environment word,
#	and every other command line is a usage error.
sub _run ( $app, @argv )
{
	my $cli = $app->cli;
	my $log = $cli->log;

	return $cli->command_usage_error('deps') if @argv != 1;
	my ($env) = @argv;
	unless ( grep { $_ eq $env } ENVIRONMENTS ) {
		$log->error(
			q{unknown environment '%s': the environments are}
			    . ' %s',
			$env, join ', ', ENVIRONMENTS
		);
		return $cli->command_usage_error('deps');
	}

	my $os   = $cli->option('os')   // ( uname() )[0];
	my $arch = $cli->option('arch') // ( uname() )[4];

	# Both words reach a file name: the system name names the
	# manifest, and each one names a download of the alias
	# expansion.
	for my $word ( [ os => $os ], [ arch => $arch ] ) {
		next if $word->[1] =~ $FILE_NAME;
		$log->error(
			q{the %s word '%s' holds letters, digits, a dot, a}
			    . ' dash, and an underscore',
			@$word
		);
		return $cli->command_usage_error('deps');
	}

	unless ( $cli->option('dry-run') ) {
		$log->error(  'the install is absent, so the verb takes'
			    . ' --dry-run alone' );
		return EXIT_ERROR;
	}

	my $dir      = File::Spec->catdir( $app->start, 'deps' );
	my $manifest = File::Spec->catfile( $dir, "$os.txt" );
	unless ( -f $manifest ) {
		$log->notice( 'no dependencies for %s', $os );
		return EXIT_SUCCESS;
	}

	my $by_type = _manifest( $app, $manifest, $env );
	return Fugu::CLI::EXIT_CONFIG_ERROR() unless $by_type;

	my $digests =
	    _digests( $app, File::Spec->catfile( $dir, 'SHA256.txt' ) );
	return Fugu::CLI::EXIT_CONFIG_ERROR() unless $digests;

	return _install( {
			app     => $app,
			os      => $os,
			arch    => $arch,
			digests => $digests,
			hold    => [],
		},
		$by_type
	);
}

# _install($ctx, $by_type):
#	Take each type of one environment, in the order of
#	DEPS-MANIFEST-4. The method returns the exit code of the run.
sub _install ( $ctx, $by_type )
{
	my %handler = (
		pkg  => \&_packages,
		dist => \&_dists,
		cpan => \&_modules,
		bin  => \&_bins,
	);

	for my $type (TYPES) {
		my $entries = $by_type->{$type};
		next unless @$entries;

		my $code = $handler{$type}->( $ctx, @$entries );
		return $code if $code != EXIT_SUCCESS;
	}

	return EXIT_SUCCESS;
}

# _manifest($app, $file, $want):
#	The entries of one manifest, as a hash of type to array
#	(DEPS-MANIFEST-2). Whitespace separates the three fields of a
#	line, and a # at the start of the first word starts a comment.
#
#	The method validates every line, and it keeps the lines of the
#	wanted environment (DEPS-MANIFEST-3). It reports the first bad
#	line and returns undef.
sub _manifest ( $app, $file, $want )
{
	my $log  = $app->cli->log;
	my $text = Fugu::File->read($file);
	unless ( defined $text ) {
		$log->error( 'cannot read %s', $file );
		return;
	}

	my %by_type = map { $_ => [] } TYPES;
	my $n       = 0;
	for my $line ( split /\n/, $text ) {
		$n++;
		my $where = "$file:$n";
		my ( $env, $type, $name ) = split ' ', $line, 3;

		next unless defined $env;
		next if index( $env, '#' ) == 0;

		# The split with a limit keeps the tail of the line
		# intact, so the trailing whitespace goes here.
		$name =~ s/\s+\z// if defined $name;

		if ( !defined $type || !defined $name || $name eq '' ) {
			$log->error(
				'%s: a line holds an environment, a type, and'
				    . ' a name: %s',
				$where, $line
			);
			return;
		}

		# An unknown environment word makes a line invisible: it
		# matches no wanted environment, and the run then claims
		# success for an install that never ran.
		unless ( grep { $_ eq $env } ENVIRONMENTS ) {
			$log->error(
				q{%s: unknown environment '%s': the}
				    . ' environments are %s',
				$where, $env, join ', ', ENVIRONMENTS
			);
			return;
		}
		unless ( exists $by_type{$type} ) {
			$log->error( q{%s: unknown type '%s': the types are %s},
				$where, $type, join ', ', TYPES );
			return;
		}

		return unless _check_entry( $app, $type, $name, $where, $line );

		next if defined $want && $env ne $want;
		push @{ $by_type{$type} }, $name;
	}

	return \%by_type;
}

# _check_entry($app, $type, $name, $where, $line):
#	Hold the name of one manifest line to the shape of its type. A
#	dist name is one URL, and a bin name holds the command name,
#	the URL, and, for an archive, the path of the file in the
#	archive (DEPS-MANIFEST-8). A pkg name and a cpan name reach a
#	package manager, so neither reads as an option, and neither
#	names a download that no tier covers (DEPS-MANIFEST-7).
sub _check_entry ( $app, $type, $name, $where, $line )
{
	my $log = $app->cli->log;

	return _check_url( $app, $name, $where ) if $type eq 'dist';

	if ( $type eq 'cpan' || $type eq 'pkg' ) {
		if ( $name =~ /\A-/ ) {
			$log->error( q{%s: a %s name must not start with a}
				    . ' dash: %s',
				$where, $type, $name );
			return 0;
		}
		if ( $name =~ m{\A[a-z][a-z0-9+.-]*://}i ) {
			$log->error( '%s: a %s name must not be a URL: %s',
				$where, $type, $name );
			return 0;
		}

		return 1;
	}

	my ( $command, $url, $member ) = split ' ', $name, 3;
	if ( !defined $url || $url eq '' ) {
		$log->error(
			'%s: a bin line holds the command name, the URL, and'
			    . ' the path in an archive: %s',
			$where, $line
		);
		return 0;
	}
	if ( _archive_type($url) && !defined $member ) {
		$log->error(
			'%s: an archive URL needs the path of the file'
			    . ' in the archive: %s',
			$where, $url
		);
		return 0;
	}
	if ( !_archive_type($url) && defined $member ) {
		$log->error(
			'%s: a path in the archive needs an archive URL:'
			    . ' %s',
			$where, $url
		);
		return 0;
	}

	return 0 unless _check_url( $app, $url, $where );

	return _check_bin_names( $app, $command, $member, $where );
}

# _check_url($app, $url, $where):
#	Hold one download URL to the shapes that the digest file
#	allows (DEPS-TIER-12). The URL becomes a key of
#	deps/SHA256.txt, whose line format reserves the parenthesis
#	and the space. The URL must also name a file, which becomes
#	the name of the download in a temporary directory.
sub _check_url ( $app, $url, $where )
{
	my $log = $app->cli->log;
	my ($file) = $url =~ m{([^/]+)\z};
	if ( !defined $file || $file eq '' ) {
		$log->error( '%s: the URL names no file: %s', $where, $url );
		return 0;
	}
	if ( $url =~ /[()\s]/ ) {
		$log->error(
			'%s: the URL holds a parenthesis or a space, which the'
			    . ' line format of deps/SHA256.txt reserves: %s',
			$where, $url
		);
		return 0;
	}

	return 1;
}

# _check_bin_names($app, $name, $member, $where):
#	Hold the command name and the archive path of one bin entry to
#	the shapes that a file name allows (DEPS-INSTALL-8). The
#	command name becomes a file name in the install directory, and
#	the archive path becomes one in a temporary directory. tar and
#	unzip read a leading dash as an option, and one of those
#	options runs a command.
sub _check_bin_names ( $app, $name, $member, $where )
{
	my $log = $app->cli->log;
	unless ( $name =~ $FILE_NAME ) {
		$log->error(
			q{%s: the command name '%s' holds letters, digits, a}
			    . ' dot, a dash, and an underscore',
			$where, $name
		);
		return 0;
	}

	return 1 unless defined $member;

	my @part = split m{/}, $member;
	if ( grep { $_ eq q{..} || $_ eq q{} } @part ) {
		$log->error(
			q{%s: the archive path '%s' must hold no empty and no}
			    . ' parent segment',
			$where, $member
		);
		return 0;
	}
	if ( $member =~ /\A-/ ) {
		$log->error(
			q{%s: the archive path '%s' must not start with}
			    . ' a dash',
			$where, $member
		);
		return 0;
	}

	return 1;
}

# _digests($app, $file):
#	The digest of each download that deps/SHA256.txt records, as a
#	hash of URL to digest (DEPS-TIER-3). An absent file, and a
#	file with no line, each give the empty set.
#
#	Every other file goes to the manifest reader of Fugu::Signify,
#	which rejects a bad line, a digest that is not 64 hexadecimal
#	characters, and a duplicate key (DEPS-TIER-4). A silent skip
#	would drop a check.
sub _digests ( $app, $file )
{
	return {} unless -f $file;

	my $log  = $app->cli->log;
	my $text = Fugu::File->read($file);
	unless ( defined $text ) {
		$log->error( 'cannot read %s', $file );
		return;
	}
	return {} if $text =~ /\A\s*\z/;

	my $reader  = Fugu::Signify->new;
	my $digests = $reader->parse_manifest($text);
	unless ($digests) {
		$log->error( '%s: %s', $file, $reader->error );
		return;
	}

	return $digests;
}

# _packages($ctx, @pkgs):
#	Give the package list to the package manager of the platform
#	(DEPS-INSTALL-1). The verb gives every package of the
#	environment in one command.
sub _packages ( $ctx, @pkgs )
{
	my $os = $ctx->{os};
	$ctx->{app}
	    ->cli->log->notice( 'the OS packages: %s', join q{ }, @pkgs );

	if ( $os eq 'OpenBSD' ) {
		_trace( $ctx, 'pkg_add', @pkgs );
	}
	elsif ( $os eq 'Linux' ) {
		_trace( $ctx, 'sudo', 'apt-get', 'update' );
		_trace( $ctx, 'sudo', 'apt-get', 'install', '-y', @pkgs );
	}
	elsif ( $os eq 'Darwin' ) {
		_trace( $ctx, 'brew', 'install', @pkgs );
	}
	else {
		$ctx->{app}
		    ->cli->log->error( 'no package manager for %s', $os );
		return EXIT_ERROR;
	}

	return EXIT_SUCCESS;
}

# _dists($ctx, @urls):
#	Fetch each distribution tarball and give it to cpanm
#	(DEPS-INSTALL-5). Every entry resolves before the first fetch,
#	so a set that one entry cannot resolve installs nothing
#	(DEPS-INSTALL-9).
sub _dists ( $ctx, @urls )
{
	$ctx->{app}
	    ->cli->log->notice( 'the distributions: %s', join q{ }, @urls );

	my @resolved;
	for my $url (@urls) {
		my ($value) = _resolve( $ctx, $url, undef );
		return Fugu::CLI::EXIT_CONFIG_ERROR() unless defined $value;
		push @resolved, $value;
	}

	my @cpanm = _cpanm($ctx);
	for my $url (@resolved) {
		my ($asset) = _asset( $ctx, $url );
		return EXIT_ERROR unless defined $asset;

		_trace( $ctx, @cpanm, _options($ctx), $asset );
	}

	return EXIT_SUCCESS;
}

# _modules($ctx, @modules):
#	Install the CPAN modules of one environment with cpanm
#	(DEPS-INSTALL-2).
sub _modules ( $ctx, @modules )
{
	$ctx->{app}
	    ->cli->log->notice( 'the CPAN modules: %s', join q{ }, @modules );

	my @cpanm = _cpanm($ctx);
	_trace( $ctx, @cpanm, _options($ctx), @modules );

	return EXIT_SUCCESS;
}

# _bins($ctx, @bins):
#	Install the prebuilt binaries of one environment into
#	~/.local/bin (DEPS-INSTALL-6). A bin entry holds the command
#	name, the download URL and, for an archive, the path of the
#	file in the archive.
#
#	Every entry resolves, and takes its shape check again, before
#	the first fetch. The resolution asks no network
#	(DEPS-ALIAS-4), so an entry that no digest names stops the run
#	while the install directory is still as it was
#	(DEPS-INSTALL-9).
sub _bins ( $ctx, @bins )
{
	my $app = $ctx->{app};
	my $log = $app->cli->log;
	$log->notice( 'the binaries: %s',
		join q{ }, map { ( split q{ }, $_, 2 )[0] } @bins );

	my $home = $ENV{HOME};
	unless ( defined $home && $home ne q{} ) {
		$log->error(  'HOME is not set, and a bin entry installs'
			    . ' under it' );
		return EXIT_ERROR;
	}

	my $bindir = File::Spec->catdir( $home, '.local', 'bin' );
	_trace( $ctx, 'mkdir', '-p', $bindir );

	my @entry;
	for my $bin (@bins) {
		my ( $name, $url, $member ) = split q{ }, $bin, 3;
		return Fugu::CLI::EXIT_CONFIG_ERROR()
		    unless _check_bin_names( $app, $name, $member,
			"the entry $name" );

		( $url, $member ) = _resolve( $ctx, $url, $member );
		return Fugu::CLI::EXIT_CONFIG_ERROR() unless defined $url;

		# The alias words expand into the archive path, so the
		# shape takes its check again after the expansion
		# (DEPS-INSTALL-8).
		return Fugu::CLI::EXIT_CONFIG_ERROR()
		    unless _check_bin_names( $app, $name, $member,
			"the resolved entry $name" );

		push @entry, [ $name, $url, $member ];
	}

	for my $bin (@entry) {
		my ( $name, $url, $member ) = @$bin;
		my $file = File::Spec->catfile( $bindir, $name );

		my ( $asset, $dir ) = _asset( $ctx, $url );
		return EXIT_ERROR unless defined $asset;

		if ( defined $member ) {
			_extract( $ctx, $dir, $file, $asset, $member );
		}
		else {
			_trace( $ctx, 'cp', $asset, $file );
		}
		_trace( $ctx, 'chmod', '755', $file );
	}

	return EXIT_SUCCESS;
}

# _extract($ctx, $dir, $file, $archive, $member):
#	Install the one file $member of a checked archive as $file
#	(DEPS-INSTALL-7). tar unpacks a tar archive, and unzip unpacks
#	a zip archive. Both unpack $member alone, into the temporary
#	directory that holds the archive.
sub _extract ( $ctx, $dir, $file, $archive, $member )
{
	if ( _archive_type($archive) eq 'tar' ) {
		_trace( $ctx, 'tar', '-xzf', $archive, '-C', $dir, $member );
	}
	else {
		_trace( $ctx, 'unzip', '-q', $archive, $member, '-d', $dir );
	}
	_trace( $ctx, 'cp', File::Spec->catfile( $dir, split m{/}, $member ),
		$file );

	return;
}

# _asset($ctx, $url):
#	The path of one download, and the temporary directory that
#	holds it, in that order (DEPS-TIER-1). The method writes the
#	trace line of the fetch, which names the fetch verb
#	(DEPS-FETCH-2).
#
#	The signed manifest of a release lands beside the download, so
#	a download named SHA256 would share one path with it. The
#	download therefore takes a directory of its own.
sub _asset ( $ctx, $url )
{
	my $dir = _tempdir($ctx);
	my ($name) = $url =~ m{([^/]+)\z};

	my $asset = File::Spec->catdir( $dir, 'asset' );
	unless ( mkdir $asset ) {
		$ctx->{app}
		    ->cli->log->error( 'cannot make %s: %s', $asset, $! );
		return;
	}

	my $file = File::Spec->catfile( $asset, $name );
	_trace( $ctx, $ctx->{app}->cli->name, 'fetch', $file, $url );

	return ( $file, $dir );
}

# _cpanm($ctx):
#	The command that runs cpanm, as a list (DEPS-INSTALL-3). The
#	cpanm on PATH is the first choice, and the bare name keeps the
#	trace line readable.
#
#	Without one, the method names the standalone cpanm script in a
#	temporary directory, and this perl runs it. An install of
#	App::cpanminus does not answer here: it lands in the local
#	library of the user, and PATH does not hold it.
#
#	The method resolves the command one time, because the trace
#	holds the download of the script one time.
sub _cpanm ($ctx)
{
	return @{ $ctx->{cpanm} } if $ctx->{cpanm};

	my @cmd = ('cpanm');
	unless ( defined Fugu::Process->find_command('cpanm') ) {
		$ctx->{app}->cli->log->notice( 'cpanm is absent, and the'
			    . ' bootstrap downloads the standalone script' );

		my $script = File::Spec->catfile( _tempdir($ctx), 'cpanm' );
		_trace( $ctx, $ctx->{app}->cli->name,
			'fetch', $script, CPANM_URL );
		@cmd = ( $^X, $script );
	}
	$ctx->{cpanm} = \@cmd;

	return @cmd;
}

# _options($ctx):
#	The options that every cpanm run shares (DEPS-INSTALL-2). With
#	PERL_LOCAL_LIB_ROOT in the environment, the install lands in
#	that directory. local::lib and the setup-perl action of CI
#	each set the variable.
sub _options ($ctx)
{
	return @{ $ctx->{options} } if $ctx->{options};

	my @opts  = ('--notest');
	my $local = $ENV{PERL_LOCAL_LIB_ROOT};
	if ( defined $local && length $local ) {
		$ctx->{app}
		    ->cli->log->notice( 'the local library: %s', $local );
		push @opts, "--local-lib=$local";
	}
	$ctx->{options} = \@opts;

	return @opts;
}

# _tempdir($ctx):
#	The path of one new temporary directory. The context holds
#	each directory object, so every directory of the run stays
#	until the run ends.
sub _tempdir ($ctx)
{
	my $dir = File::Temp->newdir(
		TEMPLATE => 'fugubench-XXXXXXXX',
		TMPDIR   => 1
	);
	push @{ $ctx->{hold} }, $dir;

	return "$dir";
}

# _resolve($ctx, $url, $member):
#	The URL and the archive path with the platform words in place,
#	in that order (DEPS-ALIAS-1). The digest file selects the
#	spelling: the method forms one candidate for each alias pair,
#	and it takes the candidate that the file records
#	(DEPS-ALIAS-3). No match and more than one match are each an
#	error, and neither one asks the network (DEPS-ALIAS-4).
#
#	The method reports the failure and returns the empty list.
sub _resolve ( $ctx, $url, $member )
{
	my $log = $ctx->{app}->cli->log;

	# Each placeholder of the archive path must also sit in the
	# URL (DEPS-ALIAS-6). The archive path names a path inside the
	# archive, and only the URL selects the platform.
	for my $word (qw(os arch)) {
		next unless defined $member && $member =~ /\{$word\}/;
		next if $url =~ /\{$word\}/;
		$log->error(
			'the archive path holds {%s}, and the URL does not:'
			    . ' %s',
			$word, $url
		);
		return;
	}

	return ( $url, $member ) if $url !~ /\{(?:os|arch)\}/;

	# The digest file keys on the URL, so a candidate matches when
	# the file records that whole URL. Two candidates never share a
	# key, so more than one match is a real ambiguity.
	my @hit = grep { exists $ctx->{digests}{ $_->[0] } }
	    _candidates( $url, $ctx->{os}, $ctx->{arch} );

	unless (@hit) {
		$log->error( 'deps/SHA256.txt records no digest for %s', $url );
		$log->error(  'the file keys on the whole download URL; run'
			    . q{ 'deps --update-sums' and check each new line}
		);
		return;
	}
	if ( @hit > 1 ) {
		$log->error(
			'deps/SHA256.txt records more than one candidate'
			    . ' of %s',
			$url
		);
		$log->error( '  %s', $_->[0] ) for @hit;
		$log->error(  q{'deps --update-sums --force' keeps one}
			    . ' candidate and drops the others' );
		return;
	}

	my ( $value, $os_word, $arch_word ) = @{ $hit[0] };

	return ( $value,
		defined $member
		? _expand( $member, $os_word, $arch_word )
		: undef );
}

# _candidates($text, $os, $arch):
#	Every distinct expansion of one text, in preference order,
#	with the word pair that made each one.
sub _candidates ( $text, $os, $arch )
{
	my ( @out, %seen );
	for my $os_word ( _os_words($os) ) {
		for my $arch_word ( _arch_words($arch) ) {
			my $value = _expand( $text, $os_word, $arch_word );
			next if $seen{$value}++;
			push @out, [ $value, $os_word, $arch_word ];
		}
	}

	return @out;
}

# _os_words($os):
#	Every asset spelling of one system name, in preference order.
#	An unknown name gives its own lower case (DEPS-ALIAS-2).
sub _os_words ($os)
{
	return @{ $OS_ALIAS{$os} // [ lc $os ] };
}

# _arch_words($arch):
#	Every asset spelling of one machine name, in preference order.
#	An unknown name gives itself (DEPS-ALIAS-2).
sub _arch_words ($arch)
{
	return @{ $ARCH_ALIAS{$arch} // [$arch] };
}

# _expand($text, $os_word, $arch_word):
#	One text with both placeholders replaced.
sub _expand ( $text, $os_word, $arch_word )
{
	my $out = $text;
	$out =~ s/\{os\}/$os_word/g;
	$out =~ s/\{arch\}/$arch_word/g;

	return $out;
}

# _archive_type($url):
#	The archive type that the suffix of the URL names: tar for
#	.tar.gz and .tgz, zip for .zip, and undef for a plain file.
sub _archive_type ($url)
{
	return 'tar' if $url =~ /\.(?:tar\.gz|tgz)\z/;
	return 'zip' if $url =~ /\.zip\z/;

	return;
}

# _trace($ctx, @cmd):
#	Print one command of the run to standard output, as the line
#	that starts with '+ ' and holds each argument shell-quoted
#	(DEPS-MANIFEST-6). The trace is the oracle of
#	CLI-CONFORMANCE-2, so the form of the line comes from the
#	synced scripts/deps.
sub _trace ( $, @cmd )
{
	say '+ ', join q{ }, map { _quote($_) } @cmd;

	return;
}

# _quote($word):
#	Shell-quote one word of the trace line. The program gives no
#	word to a shell (CLI-PROGRAM-6). The quoting lets a reader of
#	the trace, and the oracle test, see that an argument with a
#	space is one argument.
sub _quote ($word)
{
	return $word unless $word eq q{} || $word =~ /[^\w.\/:=-]/;

	my $quoted = $word;
	$quoted =~ s/'/'\\''/g;

	return "'$quoted'";
}

1;
