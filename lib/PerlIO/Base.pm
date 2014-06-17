package PerlIO::Base;

use strict;
use warnings;

use Errno qw/EINVAL EBADF/;
use PerlIO::Constants ':all';

my $flags = PERLIO_F_CANREAD | PERLIO_F_CANWRITE | PERLIO_F_TRUNCATE | PERLIO_F_APPEND;

sub pushed {
	my ($f, $mode, $arg, $vtable) = @_;
	my $self = PerlIO::self($f);

	$self->{flags} &= ~$flags;
	if ($mode =~ s/ \A \+ //x) {
		$self->{flags} |= PERLIO_F_CANREAD | PERLIO_F_CANWRITE;
	}
	if ($mode eq '<') {
		$self->{flags} |= PERLIO_F_CANREAD;
	}
	elsif ($mode eq '>') {
		$self->{flags} |= PERLIO_F_CANWRITE | PERLIO_F_TRUNCATE;
	}
	elsif ($mode eq '>>') {
		$self->{flags} |= PERLIO_F_CANWRITE | PERLIO_F_APPEND;
	}
	else {
		$! = EINVAL;
		return;
	}
	if ($self->{next}) {
		$self->{flags} |= $self->{next}{flags} & $flags;
	}
	return '0 but true';
}

sub binmode {
	my $f = shift;
	if (PerlIO::valid($f)) {
		my $self = PerlIO::self($f);
		# Is layer suitable for raw stream ?
		if ($self->tab && $self->{vtable}->kind & PERLIO_K_RAW) {
			# Yes - turn off UTF-8-ness, to undo UTF-8 locale effects */
			$self->{flags} &= ~PERLIO_F_UTF8;
		}
		else {
			# Not suitable - pop it
			PerlIO::pop($f);
		}
		return '0 but true';
	}
	return;
}

sub popped {
	return '0 but true';
}

sub error {
	my $f = shift;
	return PerlIO::self($f)->{flags} & PERLIO_F_ERROR;
}

sub eof {
	my $f = shift;
	return PerlIO::self($f)->{flags} & PERLIO_F_EOF;
}

sub fileno {
	my $f = shift;
	return PerlIO::fileno(PerlIO::next($f)) if PerlIO::valid($f);
	return;
}

sub close {
	my $f = shift;
	if (PerlIO::valid($f)) {
		my $next = PerlIO::next($f);
		my $self = PerlIO::self($f);
		my $ret = PerlIO::flush($f);
		$self->{flags} &= ~(PERLIO_F_CANREAD | PERLIO_F_CANWRITE | PERLIO_F_OPEN);
		if (PerlIO::valid($next)) {
			my $next_table = PerlIO::self($next)->{vtable};
			if (my $closer = $next_table->{close}) {
				return if not defined $closer->($next);
			}
			else {
				$self->{flags} &= ~(PERLIO_F_CANREAD | PERLIO_F_CANWRITE | PERLIO_F_OPEN);
			}
			$next = PerlIO::next($next);
		}
	}
	else {
		$! = EBADF;
	}
	return;
}

sub noop_ok {
	return '0 but true';
}

sub noop_fail {
	return;
}

1;
