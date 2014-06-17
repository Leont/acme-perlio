package PerlIO::Unix;

use strict;
use warnings;

use PerlIO::Util qw/allocate/;
use PerlIO::Base ();
use PerlIO::Constants ':all';

use POSIX qw/SEEK_CUR :fcntl_h/;
use Errno qw/EINTR EAGAIN EBADF EINVAL/;

sub _mode_to_unix {
	my $mode = shift;

	my ($extra, $main) = $mode =~ / \A (\+?) ([<>]+) \z /x;
	my $ret;
	if ($main eq '<') {
		$ret = $extra ? O_RDWR : O_RDONLY;
	}
	elsif ($mode eq '>') {
		$ret = O_CREAT | O_TRUNC | ($extra ? O_RDWR : O_WRONLY);
	}
	elsif ($mode eq '>>') {
		$ret = O_CREAT | O_APPEND | ($extra ? O_RDWR : O_WRONLY);
	}
	else {
		$! = EINVAL;
		return;
	}
	return $ret;
}

sub _set_fd {
	my ($f, $fd, $imode) = @_;
	my $self = PerlIO::self($f);
	$self->{fd} = $fd;
	return;
}

sub open {
	my ($vtable, $layerlist, $n, $mode, @args) = @_;
	my $imode = _mode_to_unix($mode);
	my $fd = POSIX::open($args[0], $imode, oct '666');
	my $f = PerlIO::Util::allocate();
	if (not PerlIO::push($f, $vtable, $mode, $layerlist->[$n]{arg})) {
		PerlIO::close($f);
		return;
	}
	_set_fd($f, $fd, $imode);
	return $f;
}

sub pushed {
	my ($f, $mode, $arg, $vtable) = @_;
	my $ret = PerlIO::Base::pushed($f, $mode, $arg, $vtable);
	if (PerlIO::valid(PerlIO::next($f))) {
		my $next = PerlIO::next($f);
		PerlIO::flush($next);
		_set_fd($f, PerlIO::fileno($next), _mode_to_unix($mode));
	}
	PerlIO::self($f)->{flags} |= PERLIO_F_OPEN;
	return $ret;
}

sub close {
	my $f = shift;
	my $self = PerlIO::self($f);
	if (!($self->{flags} & PERLIO_F_OPEN)) {
		$! = EBADF;
		return;
	}
	while (not defined POSIX::close($self->{fd})) {
		return if $! != EINTR;
	}
	return '0 but true';
}

sub fileno {
	my $f = shift;
	return PerlIO::self($f)->{fd};
}

sub read {
	my ($f, $buf_ref, $count) = @_;
	my $self = PerlIO::self($f);
	my $fd = $self->{fd};
	if (!($self->{flags} & PERLIO_F_CANREAD) || $self->{flags} & (PERLIO_F_EOF|PERLIO_F_ERROR)) {
		return 0;
	}
	while (1) {
		my $len = POSIX::read($fd, ${$buf_ref}, $count);
		if ($len >= 0 || $! != EINTR) {
			if ($len < 0) {
				if ($! != EAGAIN) {
					$self->{flags} |= PERLIO_F_ERROR;
				}
			}
			elsif ($len == 0 && $count != 0) {
				$self->{flags} |= PERLIO_F_EOF;
				$! = 0;
			}
			return $len;
		}
	}
}

sub write {
	my ($f, $buf, $count) = @_;
	my $self = PerlIO::self($f);
	my $fd = $self->{fd};
	while (1) {
		my $len = POSIX::write($fd, $buf, $count);
		if ($len >= 0 || $! != EINTR) {
			if ($len < 0) {
				if ($! != EAGAIN) {
					$self->{flags} |= PERLIO_F_ERROR;
				}
			}
			return $len;
		}
	}
}

sub seek {
	my ($f, $offset, $whence) = @_;
	my $self = PerlIO::self($f);
	my $ret = POSIX::seek($self->{fd}, $offset, $whence);
	return if not defined $ret;
	$self->{flags} &= ~PERLIO_F_EOF;
	return '0 but true';

}

sub tell {
	my $f = shift;
	return POSIX::seek(PerlIO::self($f)->{fd}, 0, SEEK_CUR);
}

PerlIO::define_layer({
	name    => 'unix',
	size    => 1,
	kind    => PERLIO_K_RAW,
	pushed  => \&pushed,
	popped  => \&PerlIO::Base::popped,
	open    => \&open,
	binmode => \&PerlIO::Base::binmode,
	fileno  => \&fileno,
	read    => \&read,
	write   => \&write,
	seek    => \&seek,
	tell    => \&tell,
	close   => \&close,
	flush   => \&PerlIO::Base::noop_ok,
	fill    => \&PerlIO::Base::noop_fail,
	eof     => \&PerlIO::Base::eof,
	error   => \&PerlIO::Base::error,
});

1;
