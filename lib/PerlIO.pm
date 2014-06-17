package PerlIO;

use strict;
use warnings;

require PerlIO::Unix;
require PerlIO::Buf;

my %table_of_tables;

sub define_layer {
	my $vtable = shift;
	$table_of_tables{ $vtable->{name} } = $vtable;
	return;
}

sub self {
	my $f = shift;
	return ${$f};
}

sub next {
	my $f = shift;
	return \${$f}->{next};
}

sub valid {
	my $f = shift;
	return $f && ${$f};
}

sub fastgets {
	my $f = shift;
	return defined ${$f}->{vtable}{peek};
}

sub _resolve_layers {
	my $layerstring = shift || ':unix:perlio';
	my (undef, @items) = split /:/, $layerstring;
	my @ret;
	for my $item (@items) {
		my ($name, $argument) = $item =~ / \A (\w+) (?: \( (.*?) \) )? \z /x;
		return if not defined $name;
		my $vtable = $table_of_tables{$name};
		return $name if not $vtable;
		push @ret, { vtable => $vtable, arg => $argument };
	}
	return \@ret;
}

sub default_bottom {
	return $table_of_tables{unix};
}

sub open {
	my ($mode, @args) = @_;
	# $vtable, $layerlist, $n, 
	my ($lowmode, $layerstring) = $mode =~ / \A ( \+? (?: < | > | >> ) ) ( (?> :\w+ )* ) \z /x;
	my $layerlist = _resolve_layers($layerstring);
	return if not $layerlist;
	my $n = $#{$layerlist};
	my $tab;
	while ($n >= 0) {
		my $t = $layerlist->[$n]{vtable};
		if ($t->{open}) {
			$tab = $t;
			last;
		}
		$n--;
	}
	if ($tab) {
		my $f = $tab->{open}->($tab, $layerlist, $n, $lowmode, @args);
		if ($f) {
			for my $o ($n + 1 .. $#{$layerlist}) {
				my $layer = $layerlist->[$o];
				if (not defined PerlIO::push($f, $mode, $layer->{arg}, $layer->{vtable})) {
					PerlIO::close($f);
					return;
				}
			}
			return $f;
		}
	}
	return;
}

sub push {
	my ($f, $vtable, $mode, $arg) = @_;
	if ($vtable->{size}) {
		my %l = (
			next   => PerlIO::self($f),
			vtable => $vtable,
			flags  => 0,
		);
		${$f} = \%l;
		if ($vtable->{pushed} and not $vtable->{pushed}->($f, $mode, $arg, $vtable)) {
			PerlIO::pop($f);
			return;
		}

	}
	elsif ($f) {
		return if $vtable->{pushed} and not $vtable->{pushed}->($f, $mode, $arg, $vtable);
	}
	return $f;
}

sub close {
	my $f = shift;
	my $self = self($f);
	return $self->{vtable}{close}->($f);
}

sub fileno {
	my $f = shift;
	my $self = self($f);
	return $self->{vtable}{fileno}->($f);
}

sub tell {
	my $f = shift;
	my $self = self($f);
	return $self->{vtable}{fileno}->($f);
}

sub read {
	my ($f, $buf_ref, $size) = @_;
	my $self = self($f);
	return $self->{vtable}{read}->($f, $buf_ref, $size);
}

sub write {
	my ($f, $buf, $size) = @_;
	my $self = self($f);
	return $self->{vtable}{write}->($f, $buf, $size);
}

sub flush {
	my $f = shift;
	my $self = self($f);
	return $self->{vtable}{flush}->($f);
}

sub fill {
	my $f = shift;
	my $self = self($f);
	return $self->{vtable}{fill}->($f);
}

sub get_cnt {
	my $f = shift;
	my $self = self($f);
	return $self->{vtable}{get_cnt}->($f);
}

sub eof {
	my $f = shift;
	my $self = self($f);
	return $self->{vtable}{eof}->($f);
}

sub error {
	my $f = shift;
	my $self = self($f);
	return $self->{vtable}{error}->($f);
}

sub peek {
	my $f = shift;
	my $self = self($f);
	return $self->{vtable}{peek}->($f);
}

sub readline {
	my $f = shift;
	my $self = PerlIO::self($f);
	return if PerlIO::eof($f);
	if (PerlIO::fastgets($f)) {
		PerlIO::fill($f) if not PerlIO::get_cnt($f);
		my $collector = '';
		while (!PerlIO::eof($f)) {
			my $buffer = PerlIO::peek($f);
			if (my $pos = index($buffer, $/) > -1) {
				PerlIO::read($f, \my $more, $pos + length $/);
				$collector .= $more;
				return $collector
			}
			else {
				PerlIO::read($f, \my $more, length $buffer);
				$collector .= $more;
				PerlIO::fill($f);
			}
		}
	}
	else {
		my $buffer = '';
		while (length($buffer) < length $/ or substr($buffer, -length($/)) ne $/) {
			last if not PerlIO::read($f, \my $char, 1);
			$buffer .= $char;
		}
		return $buffer;
	}
	return;
}

sub get_layers2 {
	my $f = shift;
	my @ret;
	while (PerlIO::valid($f)) {
		unshift @ret, PerlIO::self($f)->{vtable}{name};
		$f = PerlIO::next($f);
	}
	return @ret;
}

1;

