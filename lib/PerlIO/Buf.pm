package PerlIO::Buf;

use strict;
use warnings;

use PerlIO::Base ();
use PerlIO::Constants ':all';

use Errno qw/EBADF/;
use POSIX qw/SEEK_SET/;

my $bottom = PerlIO::default_bottom();

sub open {
	my ($vtable, $layerlist, $n, $mode, @args) = @_;
	
	my ($next, $l, $o) = ($n > 0) ? ($layerlist->[$n - 1]{vtable}, $layerlist, $n - 1) : ($bottom, [ { vtable => $bottom, arg => undef } ], 0) ;
	my $f = $next->{open}->($next, $l, $o, $mode, @args);
	if ($f) {
		if (not defined PerlIO::push($f, $vtable, $mode, $layerlist->[$n]{arg})) {
			PerlIO::close($f);
			return;
		}
	}
	return $f;
}

sub pushed {
	my ($f, $mode, $arg, $vtable) = @_;
	my $fd = PerlIO::fileno($f);
	my $self = PerlIO::self($f);
	@{$self}{qw/buffer ptr bufsiz/} = ('', 0, 4096);
	if (POSIX::isatty($fd)) {
		$self->{flags} |= PERLIO_F_LINEBUF | PERLIO_F_TTY;
	}
	if (PerlIO::valid(PerlIO::next($f))) {
		my $pos = PerlIO::tell(PerlIO::next($f));
		if (defined $pos) {
			$self->{posn} = $pos;
		}
	}
	return PerlIO::Base::pushed($f, $mode, $arg, $vtable);
}

sub flush {
	my $f = shift;
	my $self = PerlIO::self($f);
	my $next = PerlIO::next($f);
	my $ret = '0 but true';
	if ($self->{flags} & PERLIO_F_WRBUF) {
		my $p = 0;
		while ($p < length $self->{buffer}) {
			my $count = PerlIO::write($next, substr($self->{buffer}, $p), length($self->{buffer}) - $p);
			if ($count > 0) {
				$p += $count;
			}
			elsif ($count < 0 || PerlIO::error($next)) {
				$self->{flags} |= PERLIO_F_ERROR;
				$ret = undef;
				last;
			}
		}
		$self->{pos} += $p;
	}
	elsif ($self->{flags} & PERLIO_F_RDBUF) {
		$self->{posn} += $self->{ptr};
		if ($self->{ptr} != length $self->{buffer}) {
			if (PerlIO::valid($next) && defined PerlIO::seek($next, $self->{posn}, SEEK_SET)) {
				$self->{posn} = PerlIO_tell($next = PerlIO::next($f));
			}
			else {
				$self->{posn} -= $self->{ptr};
				return $ret;
			}
		}
	}
	$self->{buffer} = '';
	$self->{ptr} = 0;
	$self->{flags} &= ~(PERLIO_F_RDBUF | PERLIO_F_WRBUF);
	return if not defined PerlIO::flush($next);
	return $ret;
}

sub fill {
	my $f = shift;
	my $self = PerlIO::self($f);
	return if not defined PerlIO::flush($f);

	$self->{buffer} = '';
	$self->{ptr} = 0;

	my $next = PerlIO::next($f);
	if (!PerlIO::valid($next)) {
		$self->{flags} |= PERLIO_F_EOF;
		return;
	}

	my $avail = 0;
	if (PerlIO::fastgets($next)) {
		$avail = PerlIO::get_cnt($next);
		if ($avail <= 0) {
			my $ret = PerlIO::fill($next);
			if (defined $ret) {
				$avail = PerlIO::get_cnt($next);
			}
			else {
				$avail = !PerlIO::error($next) && PerlIO::eof($next) ? 0 : -1;
			}
		}
		if ($avail > 0) {
			my $count = $avail;
			$avail = $self->{bufsiz} if $avail > $self->{bufsiz};
			PerlIO::read($next, \$self->{buffer}, $avail);    #XXX
		}
	}
	else {
		$avail = PerlIO::read($next, \$self->{buffer}, $self->{bufsiz});
	}
	if ($avail == 0) {
		$self->{flags} |= PERLIO_F_EOF;
		return;
	}
	elsif ($avail < 0) {
		$self->{flags} |= PERLIO_F_ERROR;
		return;
	}
	$self->{flags} |= PERLIO_F_RDBUF;
	return '0 but true';
}

sub read {
	my ($f, $bufref, $count) = @_;
	if (PerlIO::valid($f)) {
		my $self = PerlIO::self($f);
        if (!($self->{flags} & PERLIO_F_CANREAD)) {
			$self->{flags} |= PERLIO_F_ERROR;
			$! = EBADF;
			return 0;
		}
		${$bufref} = '';
		while ($count > 0) {
			my $avail = length($self->{buffer}) - $self->{ptr};
			my $take = $avail > 0 ? $count > 0 && $count < $avail ? $count : $avail : 0;
			if ($take > 0) {
				${$bufref} .= substr $self->{buffer}, $self->{ptr}, $take;
				$self->{ptr} += $take;
				$count -= $take;
				$avail -= $take;
				redo if $avail == 0;
			}
			if ($count > 0 && $avail <= 0) {
				last if not defined PerlIO::fill($f);
			}
		}
		return length ${$bufref};
	}
	return 0;
}

sub write {
	my ($f, $buf, $count) = @_;
	my $self = PerlIO::self($f);
	if (!($self->{flags} & PERLIO_F_CANWRITE)) {
		$self->{flags} |= PERLIO_F_ERROR;
		$! = EBADF;
		return 0;
	}
	return 0 if $self->{flags} & PERLIO_F_RDBUF and not defined PerlIO::flush($f);
	# XXX linebuffering
	my ($pos, $flushptr, $written) = (0, 0, 0);
	while ($count > 0) {
		my $avail = $self->{bufsiz} - $self->{ptr};
		$avail = $count if $count > 0 && $count < $avail;
		$avail = $flushptr - $pos if $flushptr > $pos && $flushptr < $pos + $avail;
		$self->{flags} |= PERLIO_F_WRBUF;
		if ($avail) {
			substr $self->{buffer}, $self->{ptr}, $avail, substr $buf, $pos, $avail;
			$count -= $avail;
			$pos += $avail;
			$written += $avail;
			$self->{ptr} += $avail;
			PerlIO::flush($f) if $pos == $flushptr;
		}
		return if $self->{ptr} >= $self->{bufsiz} and not defined PerlIO::flush($f);
	}
	PerlIO::flush($f) if $self->{flags} & PERLIO_F_UNBUF;
    return $written;
}

sub get_cnt {
	my $f = shift;
	my $self = PerlIO::self($f);
	return length($self->{buffer}) - $self->{ptr};
}

sub seek {
	my ($f, $offset, $whence) = @_;
	my $self = PerlIO::self($f);
	my $ret = PerlIO::flush($f);
	if (defined $ret) {
		$self->{flags} &= ~PERLIO_F_EOF;
		$ret = PerlIO::seek(PerlIO::next($f), $offset, $whence);
		$self->{posn} = PerlIO::tell(PerlIO::next($f)) if $ret == 0;
	}
	return $ret;
}

sub tell {
	my $f = shift;
	my $self = PerlIO::self($f);
	# b->posn is file position where b->buf was read, or will be written
	my $posn = $self->{posn};
	if (($self->{flags} & PERLIO_F_APPEND) && ($self->{flags} & PERLIO_F_WRBUF)) {
		# As O_APPEND files are normally shared in some sense it is better to flush
		PerlIO::flush($f);
		$posn = $self->posn = PerlIO::tell(PerlIO::next($f));
	}
	$posn += $self->{ptr} if length $self->{buffer};
	return $posn;
}

sub close {
	my $f = shift;
	my $ret = PerlIO::Base::close($f);
	my $self = PerlIO::self($f);
	@{$self}{qw/buffer ptr/} = ('', 0);
	$self->{flags} &= ~(PERLIO_F_RDBUF | PERLIO_F_WRBUF);
	return $ret;
}

sub peek {
	my $f = shift;
	my $self = PerlIO::self($f);
	return substr $self->{buffer}, $self->{ptr};
}

PerlIO::define_layer({
	name    => 'perlio',
	size    => 1,
	kind    => PERLIO_K_BUFFERED|PERLIO_K_RAW,
	pushed  => \&pushed,
	popped  => \&PerlIO::Base::popped,
	open    => \&open,
	binmode => \&PerlIO::Base::binmode,
	fileno  => \&PerlIO::Base::fileno,
	read    => \&read,
	write   => \&write,
	seek    => \&seek,
	tell    => \&tell,
	close   => \&close,
	flush   => \&flush,
	fill    => \&fill,
	eof     => \&PerlIO::Base::eof,
	error   => \&PerlIO::Base::error,
	get_cnt => \&get_cnt,
	peek    => \&peek,
});

1;
