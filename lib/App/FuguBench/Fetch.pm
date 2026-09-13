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

package App::FuguBench::Fetch;

use v5.34;
use warnings;
use experimental 'signatures';
no feature qw(indirect multidimensional bareword_filehandles);

use Fugu::CLI qw(EXIT_SUCCESS EXIT_ERROR);
use Fugu::Curl;

# App::FuguBench::Fetch - the fetch verb.
#
# The verb downloads one URL to one file through Fugu::Curl, which
# runs curl, wget, or ftp (DEPS-FETCH-1). It takes the argument order
# of the ftp helper of Tooling: the file first, and the URL after it
# (DEPS-FETCH-2). A make recipe that called the helper calls the verb,
# and the deps verb names it in the trace of a download.
#
# The verb reads no checkout (CLI-CHECKOUT-5), so it runs in a tree
# with no .toolingrc.
#
# Fugu::Curl writes the bytes beside the destination and renames the
# file on success, so a failed download leaves no file. The verb
# reports the reason of a failure and returns 1.

# App::FuguBench::Fetch->command($verb):
#	The entry of the Fugu::CLI table. The module holds one verb,
#	so it ignores the name.
sub command ( $, $ )
{
	return {
		summary => 'download one URL to one file',
		usage   => '<file> <url>',
		run     => sub ( $app, @argv ) { return _run( $app, @argv ) },
	};
}

# _run($app, @argv):
#	The body of the verb. The arguments are the destination file
#	and the URL, in that order, and every other command line is a
#	usage error.
sub _run ( $app, @argv )
{
	my $cli = $app->cli;

	return $cli->command_usage_error('fetch') if @argv != 2;
	my ( $file, $url ) = @argv;

	# Fugu::Curl reports an absent downloader as a failed fetch,
	# so one branch covers it and every other failure.
	my $curl = Fugu::Curl->new;
	unless ( $curl->fetch( $url, $file ) ) {
		$cli->log->error( '%s', $curl->error );
		return EXIT_ERROR;
	}

	return EXIT_SUCCESS;
}

1;
