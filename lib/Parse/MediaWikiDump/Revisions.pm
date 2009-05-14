package Parse::MediaWikiDump::Revisions;

our $VERSION = '0.91';

use strict;
use warnings;
use List::Util;
use Object::Destroyer;
use Data::Dumper;

#public methods
sub new {
	my ($class, $source) = @_;
	my $self = {};

	bless($self, $class);

	$$self{XML} = undef; #holder for XML::Accumulator
	$$self{EXPAT} = undef; #holder for expat under XML::Accumulator
	$$self{SITEINFO} = {}; #holder for the data from siteinfo
	$$self{PAGE_LIST} = []; #place to store articles as they come out of XML::Accumulator
	$$self{BYTE} = 0;
	$$self{CHUNK_SIZE} = 32768;
	$$self{FINISHED} = 0;

	$self->open($source);
	$self->init;
	
	return $self;
}

sub next {
	my ($self) = @_;
	my $case = $self->{SITEINFO}->{CASE};
	my $namespaces = $self->{SITEINFO}->{namespaces};
	
	my $page;
	
	while(1) {
		$page = shift(@{ $self->{PAGE_LIST} } );
		
		if (defined($page)) {
			
			return Parse::MediaWikiDump::page->new($page, $self->get_category_anchor, $case, $namespaces);
		}
		
		return undef unless $self->parse_more;		
	}
	
	die "should not get here";
}

sub sitename {
	my ($self) = @_;
	return $$self{SITEINFO}{sitename};
}

sub base {
	my ($self) = @_;
	return $$self{SITEINFO}{base};
}

sub generator {
	my ($self) = @_;
	return $$self{SITEINFO}{generator};
}

sub case {
	my ($self) = @_;
	return $$self{SITEINFO}{case};
}

sub namespaces {
	my ($self) = @_;
	return $$self{SITEINFO}{namespaces};
}

sub namespaces_names {
	my $self = shift;
	my @result;
	
	foreach (@{ $$self{SITEINFO}{namespaces} }) {
		push(@result, $_->[1]);
	}
	
	return \@result;
}

sub current_byte {
	my ($self) = @_;
	return $$self{BYTE};
}

sub size {
	my ($self) = @_;
	
	return undef unless defined $$self{SOURCE_FILE};

	my @stat = stat($$self{SOURCE_FILE});

	return $stat[7];
}

#private functions with OO interface

#sub cleanup {
#	my ($self) = @_;
#	
#	warn "executing cleanup";
#	
##	$self->{EXPAT} = undef;	
##	$self->{XML} = undef;
#}

sub open {
	my ($self, $source) = @_;

	if (ref($source) eq 'GLOB') {
		$$self{SOURCE} = $source;
	} else {
		if (! open($$self{SOURCE}, $source)) {
			die "could not open $source: $!";
		}

		$$self{SOURCE_FILE} = $source;
	}

	binmode($$self{SOURCE}, ':utf8');

	return 1;
}

sub init {
	my ($self) = @_;
	
	$self->{XML} = $self->new_accumulator_engine;
	my $expat_bb = $$self{XML}->parser->parse_start();
	$$self{EXPAT} = Object::Destroyer->new($expat_bb, 'parse_done');
	
	#load the information from the siteinfo section so it is available before
	#someone calls ->next
	while(1) {
		if (scalar(@{$self->{PAGE_LIST}}) > 1) {
			last;
		}	
		
		$self->parse_more;	
	}
}

sub new_accumulator_engine {
	my ($self) = @_;
	my $f = Parse::MediaWikiDump::XML::Accumulator->new;
	my $store_siteinfo = $self->{SITEINFO};
	my $store_page = $self->{PAGE_LIST};
	
	my $root = $f->root;
	my $mediawiki = $f->node('mediawiki', Start => \&validate_mediawiki_node);
	
	#stuff for siteinfo
	my $siteinfo = $f->node('siteinfo', End => sub { %$store_siteinfo = %{ $_[1] } } );
	my $sitename = $f->textcapture('sitename');
	my $base = $f->textcapture('base');
	my $generator = $f->textcapture('generator');
	my $case = $f->textcapture('case');
	my $namespaces = $f->node('namespaces', Start => sub { $_[1]->{namespaces} = []; } );
	my $namespace = $f->node('namespace', Character => \&save_namespace_node);
	
	#stuff for page entries
	my $page = $f->node('page', Start => sub { $_[0]->accumulator( {} ) } );
	my $title = $f->textcapture('title');
	my $id = $f->textcapture('id');
	my $revision = $f->node('revision', 
		Start => sub { $_[1]->{minor} = 0 }, End => sub { push(@$store_page, { %{ $_[1] } } ) } );
	my $rev_id = $f->textcapture('id', 'revision_id');
	my $minor = $f->node('minor', Start => sub { $_[1]->{minor} = 1 } );
	my $time = $f->textcapture('timestamp');
	my $contributor = $f->node('contributor');
	my $username = $f->textcapture('username');
	my $ip = $f->textcapture('ip');
	my $contrib_id = $f->textcapture('id', 'userid');
	my $comment = $f->textcapture('comment');
	my $text = $f->textcapture('text');
	my $restr = $f->textcapture('restrictions');
	
	#put together the tree
	$siteinfo->add_child($sitename, $base, $generator, $case, $namespaces);
	  $namespaces->add_child($namespace);
	
	$page->add_child($title, $id, $revision, $restr);
	  $revision->add_child($rev_id, $time, $contributor, $minor, $comment, $text);
	    $contributor->add_child($username, $ip, $contrib_id);
	
	$mediawiki->add_child($siteinfo, $page);
	$root->add_child($mediawiki);
	
	my $engine = $f->engine($root, {});

	return $engine;	
}

sub parse_more {
        my ($self) = @_;
        my $buf;

        my $read = read($$self{SOURCE}, $buf, $$self{CHUNK_SIZE});

        if (! defined($read)) {
                die "error during read: $!";
        } elsif ($read == 0) {
                $$self{FINISHED} = 1;
                $$self{EXPAT} = undef; #Object::Destroyer cleans this up
                return 0;
        }

        $$self{BYTE} += $read;
        $$self{EXPAT}->parse_more($buf);

        return 1;
}

sub get_category_anchor {
	my ($self) = @_;
	my $namespaces = $self->{SITEINFO}->{namespaces};

	foreach (@$namespaces) {
		my ($id, $name) = @$_;
		if ($id == 14) {
			return $name;
		}
	}	
	
	return undef;
}

#sub save_page {
#	my ($page, $save_to) = @_;
#	my %page = %$page; #make a local copy
#	
#	push(@{ $self->{PAGE_LIST} }, \%page);
#}


#helper functions that the xml accumulator uses
sub save_namespace_node {
	my ($parser, $accum, $text, $element, $attrs) = @_;
	my $key = $attrs->{key};
	my $namespaces = $accum->{namespaces};
	
	push(@{ $accum->{namespaces} }, [$key, $text] );
}

sub validate_mediawiki_node {
	my ($engine, $a, $element, $attrs) = @_;
	die "Only version 0.3 dump files are supported" unless $attrs->{version} eq '0.3';
}

sub save_siteinfo {
	my ($self, $info) = @_;
	my %info = %$info;
	
	$self->{SITEINFO} = \%info;
}

1;