package PerlIO::Constants;

use strict;
use warnings;

use constant {
	PERLIO_F_EOF      => 0x00000100,
	PERLIO_F_CANWRITE => 0x00000200,
	PERLIO_F_CANREAD  => 0x00000400,
	PERLIO_F_ERROR    => 0x00000800,
	PERLIO_F_TRUNCATE => 0x00001000,
	PERLIO_F_APPEND   => 0x00002000,
	PERLIO_F_CRLF     => 0x00004000,
	PERLIO_F_UTF8     => 0x00008000,
	PERLIO_F_UNBUF    => 0x00010000,
	PERLIO_F_WRBUF    => 0x00020000,
	PERLIO_F_RDBUF    => 0x00040000,
	PERLIO_F_LINEBUF  => 0x00080000,
	PERLIO_F_TEMP     => 0x00100000,
	PERLIO_F_OPEN     => 0x00200000,
	PERLIO_F_FASTGETS => 0x00400000,
	PERLIO_F_TTY      => 0x00800000,
	PERLIO_F_NOTREG   => 0x01000000,
	PERLIO_F_CLEARED  => 0x02000000,
};

use constant {
	PERLIO_K_RAW      => 0x00000001,
	PERLIO_K_BUFFERED => 0x00000002,
	PERLIO_K_CANCRLF  => 0x00000004,
	PERLIO_K_FASTGETS => 0x00000008,
	PERLIO_K_DUMMY    => 0x00000010,
	PERLIO_K_UTF8     => 0x00008000,
	PERLIO_K_DESTRUCT => 0x00010000,
	PERLIO_K_MULTIARG => 0x00020000,
};

sub _setup {
	my @flags = grep { /PERLIO_F_/ } keys %PerlIO::Constants::;
	my @kinds = grep { /PERLIO_K_/ } keys %PerlIO::Constants::;
	return {
		exports => [ @flags, @kinds ],
		groups  => {
			flags => \@flags,
			kinds => \@kinds,
		}
	};
}

use Sub::Exporter::Progressive -setup => _setup();

1;
