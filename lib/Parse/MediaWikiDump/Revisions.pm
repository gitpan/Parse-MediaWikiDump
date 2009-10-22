package Parse::MediaWikiDump::Revisions;

our $VERSION = '0.96';

use 5.8.0;

use strict;
use warnings;
use List::Util;
use Scalar::Util qw(weaken reftype);
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
	
	#return Object::Destroyer($self, 'cleanup');
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

sub version {
	my ($self) = @_;
	return $self->{SITEINFO}{version};
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

sub cleanup {
	my ($self) = @_;
	
	#warn "executing cleanup";
	
	$self->{EXPAT}->setHandlers(Init => undef, Final => undef, Start => undef, 
		End => undef, Char => undef);
	$self->{EXPAT}->parse_done;	
	#$self->{XML} = undef;
}

sub open {
	my ($self, $source) = @_;

	if (defined(reftype($source)) && reftype($source) eq 'GLOB') {
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
	#$$self{EXPAT} = Object::Destroyer->new($expat_bb, 'parse_done'); #causes exceptions not to be thrown
	$$self{EXPAT} = $expat_bb;
	
	#load the information from the siteinfo section so it is available before
	#someone calls ->next
	while(1) {
		if (scalar(@{$self->{PAGE_LIST}}) > 0) {
			last;
		}	
		
		$self->parse_more;	
	}
	
	#XML::Accumulator holds a copy of itself
	weaken($self->{XML});
}

sub new_accumulator_engine {
	my ($self) = @_;
	my $f = Parse::MediaWikiDump::XML::Accumulator->new;
	my $store_siteinfo = $self->{SITEINFO};
	my $store_page = $self->{PAGE_LIST};
	
	my $root = $f->root;
	my $mediawiki = $f->node('mediawiki', Start => \&handle_mediawiki_node);
	
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
                #$$self{EXPAT} = undef; #Object::Destroyer cleans this up
                $$self{EXPAT}->parse_done;
                
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

sub handle_mediawiki_node {
	my ($engine, $a, $element, $attrs) = @_;
	my $version = $attrs->{version};
	
	if ($version ne '0.3' && $version ne '0.4') {
			die "Only version 0.3 and 0.4 dump files are supported";
	}
	
	$a->{version} = $version;
}

sub save_siteinfo {
	my ($self, $info) = @_;
	my %info = %$info;
	
	$self->{SITEINFO} = \%info;
}

1;

__END__
=head1 NAME

Parse::MediaWikiDump::Revisions - Object capable of processing dump files with multiple revisions per article

=head1 ABOUT

This object is used to access the metadata associated with a MediaWiki instance and provide an iterative interface
for extracting the indidivual article revisions out of the same. To gurantee that there is only a single
revision per article use the Parse::MediaWikiDump::Revisions object. 

=head1 SYNOPSIS
  
  $pmwd = Parse::MediaWikiDump->new;
  $revisions = $pmwd->revisions('pages-articles.xml');
  $revisions = $pmwd->revisions(\*FILEHANDLE);
  
  #print the title and id of each article inside the dump file
  while(defined($page = $revisions->next)) {
    print "title '", $page->title, "' id ", $page->id, "\n";
  }

=head1 METHODS

=over 4

=item $revisions->new

Open the specified MediaWiki dump file. If the single argument to this method
is a string it will be used as the path to the file to open. If the argument
is a reference to a filehandle the contents will be read from the filehandle as
specified. 

=item $revisions->next

Returns an instance of the next available Parse::MediaWikiDump::page object or returns undef
if there are no more articles left.

=item $revisions->version

Returns a plain text string of the dump file format revision number

=item $revisions->sitename

Returns a plain text string that is the name of the MediaWiki instance.

=item $revisions->base

Returns the URL to the instances main article in the form of a string.

=item $revisions->generator

Returns a string containing 'MediaWiki' and a version number of the instance that dumped this file.
Example: 'MediaWiki 1.14alpha'

=item $revisions->case

Returns a string describing the case sensitivity configured in the instance.

=item $revisions->namespaces

Returns a reference to an array of references. Each reference is to another array with the first
item being the unique identifier of the namespace and the second element containing a string
that is the name of the namespace.

=item $revisions->namespaces_names

Returns an array reference the array contains strings of all the namespaces each as an element. 

=item $revisions->current_byte

Returns the number of bytes that has been processed so far

=item $revisions->size

Returns the total size of the dump file in bytes. 

=back

=head1 EXAMPLE

=head2 Extract the article text of each revision of an article using a given title

  #!/usr/bin/perl
  
  use strict;
  use warnings;
  use Parse::MediaWikiDump;
  
  my $file = shift(@ARGV) or die "must specify a MediaWiki dump of the current pages";
  my $title = shift(@ARGV) or die "must specify an article title";
  my $pmwd = Parse::MediaWikiDump->new;
  my $dump = $pmwd->revisions($file);
  my $found = 0;
  
  binmode(STDOUT, ':utf8');
  binmode(STDERR, ':utf8');
  
  #this is the only currently known value but there could be more in the future
  if ($dump->case ne 'first-letter') {
    die "unable to handle any case setting besides 'first-letter'";
  }
  
  $title = case_fixer($title);
  
  while(my $revision = $dump->next) {
    if ($revision->title eq $title) {
      print STDERR "Located text for $title revision ", $revision->revision_id, "\n";
      my $text = $revision->text;
      print $$text;
      
      $found = 1;
    }
  }
  
  print STDERR "Unable to find article text for $title\n" unless $found;
  exit 1;
  
  #removes any case sensativity from the very first letter of the title
  #but not from the optional namespace name
  sub case_fixer {
    my $title = shift;
  
    #check for namespace
    if ($title =~ /^(.+?):(.+)/) {
      $title = $1 . ':' . ucfirst($2);
    } else {
      $title = ucfirst($title);
    }
  
    return $title;
  }
  
=head1 LIMITATIONS

=head2 Memory Leak

This class is not performing proper garbage collection at destruction and will leak memory like crazy if 
multiple instances of it are created inside one perl script. 
