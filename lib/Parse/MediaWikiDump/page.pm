package Parse::MediaWikiDump::page;

use strict;
use warnings;
use List::Util;

sub new {
	my ($class, $data, $category_anchor, $case_setting, $namespaces) = @_; 
	my $self = {};

	bless($self, $class);

	$$self{DATA} = $data;
	$$self{CACHE} = {};
	$$self{CATEGORY_ANCHOR} = $category_anchor;
	$$self{NAMESPACES} = $namespaces;

	return $self;
}

sub namespace {
	my ($self) = @_;
	my $title = $self->title;
	my $namespace = '';
	
	#warn "size " . scalar(@{ $self->{NAMESPACES} });
	
	return $$self{CACHE}{namespace} if defined $$self{CACHE}{namespace};
	
	if ($title =~ m/^([^:]+):(.*)/) {
#		warn "got a namespace candidate: $1 - $2";

		foreach (@{ $self->{NAMESPACES} } ) {
			my ($num, $name) = @$_;
			
#			warn $name;

#			warn "$1 $name";
			
			if ($1 eq $name) {
				$namespace = $1;
				last;
			}
		}
	}

#	warn "this function is still broken";

#	warn "namespace: $namespace";
	
	$$self{CACHE}{namespace} = $namespace;

	return $namespace;
}

sub categories {
	my ($self) = @_;
	my $anchor = $$self{CATEGORY_ANCHOR};

	return $$self{CACHE}{categories} if defined($$self{CACHE}{categories});

	my $text = $$self{DATA}{text};
	my @cats;
	
	while($text =~ m/\[\[$anchor:\s*([^\]]+)\]\]/gi) {
		my $buf = $1;

		#deal with the pipe trick
		$buf =~ s/\|.*$//;
		push(@cats, $buf);
	}

	return undef if scalar(@cats) == 0;

	$$self{CACHE}{categories} = \@cats;

	return \@cats;
}

sub redirect {
	my ($self) = @_;
	my $text = $$self{DATA}{text};

	return $$self{CACHE}{redirect} if exists($$self{CACHE}{redirect});

	if ($text =~ m/^#redirect\s*:?\s*\[\[([^\]]*)\]\]/i) {
		$$self{CACHE}{redirect} = $1;
		return $1;
	} else {
		$$self{CACHE}{redirect} = undef;
		return undef;
	}
}

sub title {
	my ($self) = @_;
	return $$self{DATA}{title};
}

sub id {
	my ($self) = @_;
	return $$self{DATA}{id};
}

sub revision_id {
	my ($self) = @_;
	return $$self{DATA}{revision_id};
}

sub timestamp {
	my ($self) = @_;
	return $$self{DATA}{timestamp};
}

sub username {
	my ($self) = @_;
	return $$self{DATA}{username};
}

sub userid {
	my ($self) = @_;
	return $$self{DATA}{userid};
}

sub minor {
	my ($self) = @_;
	return $$self{DATA}{minor};
}

sub text {
	my ($self) = @_;
	return \$$self{DATA}{text};
}

1;