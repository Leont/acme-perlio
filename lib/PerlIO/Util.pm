package PerlIO::Util;

use strict;
use warnings;

use Sub::Exporter::Progressive -setup => { exports => [ qw/allocate/ ] };

sub allocate {
	my $ret;
	return \$ret;
}

1;
