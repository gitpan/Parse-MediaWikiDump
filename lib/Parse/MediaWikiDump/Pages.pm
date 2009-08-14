package Parse::MediaWikiDump::Pages;

our $VERSION = '0.92';

#This parser works by placing all of the start, text, and end events into
#a buffer as they come out of XML::Parser. On each call to page() the function
#checks for a complete article in the buffer and calls for XML::Parser to add
#more tokens if a complete article is not found. Once a complete article is 
#found it is removed from the buffer, parsed, and an instance of the page
#object is returned. 

use 5.8.0;

use strict;
use warnings;
use List::Util;
use XML::Parser;
use Carp;

sub new {
	my ($class, $source) = @_;
	my $self = {};
	my $parser_state = {}; #Hash::NoRef->new;

	bless ($self, $class);

	$$self{PARSER} = XML::Parser->new(ProtocolEncoding => 'UTF-8');
	$$self{PARSER}->setHandlers('Start', \&start_handler,
					'End', \&end_handler);

	$$self{GOOD_TAGS} = make_good_tags();
	$$self{BUFFER} = []; 
	$$self{CHUNK_SIZE} = 32768;
	$$self{BUF_LIMIT} = 10000;
	$$self{BYTE} = 0;

	$parser_state->{GOOD_TAGS} = $$self{GOOD_TAGS};
	$parser_state->{BUFFER} = $$self{BUFFER};

	my $expat_bb = $$self{PARSER}->parse_start(state => $parser_state);
	$$self{EXPAT} = Object::Destroyer->new($expat_bb, 'parse_done');

	$self->open($source);
	$self->init;

	return $self;
}

sub next {
	my ($self) = @_;
	my $buffer = $$self{BUFFER};
	my $offset;
	my @page;

	#look through the contents of our buffer for a complete article; fill
	#the buffer with more data if an entire article is not there
	while(1) {
		$offset = $self->search_buffer('/page');
		last if $offset != -1;

		#indicates EOF
		return undef unless $self->parse_more;
	}

	#remove the entire page from the buffer
	@page = splice(@$buffer, 0, $offset + 1);

	if ($page[0][0] ne 'page') {
		$self->dump($buffer);
		die "expected <page>; got " . token2text($page[0]);
	}

	my $data = $self->parse_page(\@page);

	return Parse::MediaWikiDump::page->new($data, $$self{CATEGORY_ANCHOR}, 
		$$self{HEAD}{CASE}, $$self{HEAD}{namespaces});
}

#outputs a nicely formated representation of the tokens on the buffer specified
sub dump {
	my ($self, $buffer) = @_;
	my $offset = 0;

	if (! defined($buffer)) {
		$buffer = $$self{BUFFER};
	}

	foreach my $i (0 .. $#$buffer) {
		my $token = $$buffer[$i];

		print STDERR "$i ";

		if (substr($$token[0], 0, 1) ne '/') {
			my $attr = $$token[1];
			print STDERR "  " x $offset;
			print STDERR "START $$token[0] ";

			foreach my $key (sort(keys(%$attr))) {
				print STDERR "$key=\"$$attr{$key}\" ";
			}

			print STDERR "\n";
			$offset++;
		} elsif (ref $token eq 'ARRAY') {
			$offset--;
			print STDERR "  " x $offset;
			print STDERR "END $$token[0]\n";
		} elsif (ref $token eq 'SCALAR') {
			my $ref = $token;
			print STDERR "  " x $offset;
			print STDERR "TEXT ";

			my $len = length($$ref);

			if ($len < 50) {
				print STDERR "'$$ref'\n";
			} else {
				print STDERR "$len characters\n";
			}
		}
	}
	
	return 1;
}

sub sitename {
	my ($self) = @_;
	return $$self{HEAD}{sitename};
}

sub base {
	my ($self) = @_;
	return $$self{HEAD}{base};
}

sub generator {
	my ($self) = @_;
	return $$self{HEAD}{generator};
}

sub case {
	my ($self) = @_;
	return $$self{HEAD}{case};
}

sub namespaces {
	my ($self) = @_;
	return $$self{HEAD}{namespaces};
}

sub namespaces_names {
	my $self = shift;
	return $$self{HEAD}{namespaces_names};
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

#depreciated backwards compatibility methods

#replaced by next()
sub page {
	my ($self) = @_;
	
	carp("the page() method is depreciated and is going away in the future, use next() instead");
	
	return $self->next(@_);
}

#private functions with OO interface
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
	my $offset;
	my @head;

	#parse more XML until the entire siteinfo section is in the buffer
	while(1) {
		die "could not init" unless $self->parse_more;

		$offset = $self->search_buffer('/siteinfo');

		last if $offset != -1;
	}

	#pull the siteinfo section out of the buffer
	@head = splice(@{$$self{BUFFER}}, 0, $offset + 1);

	$self->parse_head(\@head);

	return 1;
}

#feed data into expat and have it put more tokens onto the buffer
sub parse_more {
	my ($self) = @_;
	my $buf;

	my $read = read($$self{SOURCE}, $buf, $$self{CHUNK_SIZE});

	if (! defined($read)) {
		die "error during read: $!";
	} elsif ($read == 0) {
		$$self{FINISHED} = 1;
		$$self{EXPAT} = undef; #Object::Destroyer invokes parse_done()
		return 0;
	}

	$$self{BYTE} += $read;
	$$self{EXPAT}->parse_more($buf);

	my $buflen = scalar(@{$$self{BUFFER}});

	die "buffer length of $buflen exceeds $$self{BUF_LIMIT}" unless
		$buflen < $$self{BUF_LIMIT};

	return 1;
}

#searches through a buffer for a specified token
sub search_buffer {
	my ($self, $search, $list) = @_;

	$list = $$self{BUFFER} unless defined $list;

	return -1 if scalar(@$list) == 0;

	foreach my $i (0 .. $#$list) {
		return $i if ref $$list[$i] eq 'ARRAY' && $list->[$i][0] eq $search;
	}

	return -1;
}

#this function is very frightning :-( 
#a better alternative would be to have each part of the stack handled by a 
#function that handles all the logic for that specific node in the tree
sub parse_head {
	my ($self, $buffer) = @_;
	my $state = 'start';
	my %data = (
		namespaces			=> [],
		namespaces_names	=> [],
	);

	for (my $i = 0; $i <= $#$buffer; $i++) {
		my $token = $$buffer[$i];

		if ($state eq 'start') {
			my $version;
			die "$i: expected <mediawiki> got " . token2text($token) unless
				$$token[0] eq 'mediawiki';

			die "$i: version is a required attribute" unless
				defined($version = $$token[1]->{version});

			die "$i: version $version unsupported" unless $version eq '0.3';

			$token = $$buffer[++$i];

			die "$i: expected <siteinfo> got " . token2text($token) unless
				$$token[0] eq 'siteinfo';

			$state = 'in_siteinfo';
		} elsif ($state eq 'in_siteinfo') {
			if ($$token[0] eq 'namespaces') {
				$state = 'in_namespaces';
				next;
			} elsif ($$token[0] eq '/siteinfo') {
				last;
			} elsif ($$token[0] eq 'sitename') {
				$token = $$buffer[++$i];

				if (ref $token ne 'SCALAR') {
					die "$i: expected TEXT but got " . token2text($token);
				}

				$data{sitename} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/sitename') {
					die "$i: expected </sitename> but got " . token2text($token);
				}
			} elsif ($$token[0] eq 'base') {
				$token = $$buffer[++$i];

				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expected TEXT but got " . token2text($token);
				}

				$data{base} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/base') {
					$self->dump($buffer);
					die "$i: expected </base> but got " . token2text($token);
				}

			} elsif ($$token[0] eq 'generator') {
				$token = $$buffer[++$i];

				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expected TEXT but got " . token2text($token);
				}

				$data{generator} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/generator') {
					$self->dump($buffer);
					die "$i: expected </generator> but got " . token2text($token);
				}

			} elsif ($$token[0] eq 'case') {
				$token = $$buffer[++$i];

				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expected </case> but got " . token2text($token);
				}

				$data{case} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/case') {
					$self->dump($buffer);
					die "$i: expected </case> but got " . token2text($token);
				}
			}

		} elsif ($state eq 'in_namespaces') {
			my $key;
			my $name;

			if ($$token[0] eq '/namespaces') {
				$state = 'in_siteinfo';
				next;
			} 

			if ($$token[0] ne 'namespace') {
				die "$i: expected <namespace> or </namespaces>; got " . token2text($token);
			}

			die "$i: key is a required attribute" unless
				defined($key = $$token[1]->{key});

			$token = $$buffer[++$i];

			#the default namespace has no text associated with it
			if (ref $token eq 'SCALAR') {
				$name = $$token;
			} elsif ($$token[0] eq '/namespace') {
				$name = '';
				$i--; #move back one for below
			} else {
				die "$i: should never happen";	
			}

			push(@{$data{namespaces}}, [$key, $name]);
			push(@{$data{namespaces_names}}, $name);

			$token = $$buffer[++$i];

			if ($$token[0] ne '/namespace') {
				$self->dump($buffer);
				die "$i: expected </namespace> but got " . token2text($token);
			}

		} else {
			die "$i: unknown state '$state'";
		}
	}

	$$self{HEAD} = \%data;

	#locate the anchor that indicates what looks like a link is really a 
	#category assignment ([[foo]] vs [[Category:foo]])
	#fix for bug #16616
	foreach my $ns (@{$data{namespaces}}) {
		#namespace 14 is the category namespace
		if ($$ns[0] == 14) {
			$$self{CATEGORY_ANCHOR} = $$ns[1];
			last;
		}
	}

	if (! defined($$self{CATEGORY_ANCHOR})) {
		die "Could not locate category indicator in namespace definitions";
	}

	return 1;
}

#this function is very frightning :-(
#see the parse_head function comments for thoughts on improving these
#awful functions
sub parse_page {
	my ($self, $buffer) = @_;
	my %data;
	my $state = 'start';

	for (my $i = 0; $i <= $#$buffer; $i++) {
		my $token = $$buffer[$i];


		if ($state eq 'start') {
			if ($$token[0] ne 'page') {
				$self->dump($buffer);
				die "$i: expected <page>; got " . token2text($token);
			}

			$state = 'in_page';
		} elsif ($state eq 'in_page') {
			next unless ref $token eq 'ARRAY';
			if ($$token[0] eq 'revision') {
				$state = 'in_revision';
				next;
			} elsif ($$token[0] eq '/page') {
				last;
			} elsif ($$token[0] eq 'title') {
				$token = $$buffer[++$i];

				if (ref $token eq 'ARRAY' && $$token[0] eq '/title') {
					$data{title} = '';
					next;
				}

				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{title} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/title') {
					$self->dump($buffer);
					die "$i: expected </title>; got " . token2text($token);
				}
			} elsif ($$token[0] eq 'id') {
				$token = $$buffer[++$i];
	
				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{id} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/id') {
					$self->dump($buffer);
					die "$i: expected </id>; got " . token2text($token);
				}
			}
		} elsif ($state eq 'in_revision') {
			if ($$token[0] eq '/revision') {
				#If a comprehensive dump file is parsed
				#it can cause uncontrolled stack growth and the
				#parser only returns one revision out of
				#all revisions - if we run into a 
				#comprehensive dump file, indicated by more
				#than one <revision> section inside a <page>
				#section then die with a message

				#just peeking ahead, don't want to update
				#the index
				$token = $$buffer[$i + 1];

				if ($$token[0] eq 'revision') {
					die "unable to properly parse comprehensive dump files";
				}

				$state = 'in_page';
				next;	
			} elsif ($$token[0] eq 'contributor') {
				$state = 'in_contributor';
				next;
			} elsif ($$token[0] eq 'id') {
				$token = $$buffer[++$i];
	
				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{revision_id} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/id') {
					$self->dump($buffer);
					die "$i: expected </id>; got " . token2text($token);
				}

			} elsif ($$token[0] eq 'timestamp') {
				$token = $$buffer[++$i];

				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{timestamp} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/timestamp') {
					$self->dump($buffer);
					die "$i: expected </timestamp>; got " . token2text($token);
				}
			} elsif ($$token[0] eq 'minor') {
				$data{minor} = 1;
				$token = $$buffer[++$i];

				if ($$token[0] ne '/minor') {
					$self->dump($buffer);
					die "$i: expected </minor>; got " . token2text($token);
				}
			} elsif ($$token[0] eq 'comment') {
				$token = $$buffer[++$i];

				#account for possible null-text 
				if (ref $token eq 'ARRAY' && $$token[0] eq '/comment') {
					$data{comment} = '';
					next;
				}

				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{comment} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/comment') {
					$self->dump($buffer);
					die "$i: expected </comment>; got " . token2text($token);
				}

			} elsif ($$token[0] eq 'text') {
				my $token = $$buffer[++$i];

				if (ref $token eq 'ARRAY' && $$token[0] eq '/text') {
					$data{text} = '';
					next;
				} elsif (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{text} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/text') {
					$self->dump($buffer);
					die "$i: expected </text>; got " . token2text($token);
				}
			
			}

		} elsif ($state eq 'in_contributor') {
			next unless ref $token eq 'ARRAY';
			if ($$token[0] eq '/contributor') {
				$state = 'in_revision';
				next;
			} elsif (ref $token eq 'ARRAY' && $$token[0] eq 'username') {
				$token = $$buffer[++$i];

				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expecting TEXT; got " . token2text($token);
				}

				$data{username} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/username') {
					$self->dump($buffer);
					die "$i: expected </username>; got " . token2text($token);
				}

			} elsif ($$token[0] eq 'id') {
				$token = $$buffer[++$i];
				
				if (ref $token ne 'SCALAR') {
					$self->dump($buffer);
					die "$i: expecting TEXT; got " . token2text($token);
				}

				$data{userid} = $$token;

				$token = $$buffer[++$i];

				if ($$token[0] ne '/id') {
					$self->dump($buffer);
					die "$i: expecting </id>; got " . token2text($token);
				}
			}
		} else {
			die "unknown state: $state";
		}
	}

	$data{namespace} = '';
	# Many pages just have a : in the title, but it's not necessary
	# a namespace designation.
	if ($data{title} =~ m/^([^:]+)\:/) {
		my $possible_namespace = $1;
		if (List::Util::first { $_ eq $possible_namespace }
			@{ $self->namespaces_names() })
		{
			$data{namespace} = $possible_namespace;
		}
	}

	$data{minor} = 0 unless defined($data{minor});

	return \%data;
}

#private functions with out OO interface
sub make_good_tags {
	return {
		sitename => 1,
		base => 1,
		generator => 1,
		case => 1,
		namespace => 1,
		title => 1,
		id => 1,
		timestamp => 1,
		username => 1,
		comment => 1,
		text => 1
	};
}

sub token2text {
	my ($token) = @_;

	if (ref $token eq 'ARRAY') {
		return "<$$token[0]>";
	} elsif (ref $token eq 'SCALAR') {
		return "!text_token!";
	} else {
		return "!unknown!";
	}
}

#this function is where the majority of time is spent in this software
#sub token_compare {
#	my ($toke1, $toke2) = @_;
#
#	foreach my $i (0 .. $#$toke2) {
#		if ($$toke1[$i] ne $$toke2[$i]) {
#			return 0;
#		}
#	}
#
#	return 1;
#}

sub start_handler {
	my ($p, $tag, %atts) = @_;	
	my $self = $p->{state};
	my $good_tags = $$self{GOOD_TAGS};

	push @{ $$self{BUFFER} }, [$tag, \%atts];

	if (defined($good_tags->{$tag})) {
		$p->setHandlers(Char => \&char_handler);
	}

	return 1;
}

sub end_handler {
	my ($p, $tag) = @_;
	my $self = $p->{state};

	push @{ $$self{BUFFER} }, ["/$tag"];

	$p->setHandlers(Char => undef);
	
	return 1;
}

sub char_handler {
	my ($p, $chars) = @_;
	my $self = $p->{state};
	my $buffer = $$self{BUFFER};
	my $curent = $$buffer[-1];

	if (ref $curent eq 'SCALAR') {
		$$curent .= $chars;
	} elsif (substr($$curent[0], 0, 1) ne '/') {
		push(@$buffer, \$chars);
	} 

	return 1;
}

1;

__END__
=head1 NAME

Parse::MediaWikiDump::Pages - Object capable of processing dump files with a single revision per article

=head1 ABOUT

This object is used to access the metadata associated with a MediaWiki instance and provide an iterative interface
for extracting the individual articles out of the same. This module does not allow more than one revision
for each specific article; to parse a comprehensive dump file use the Parse::MediaWikiDump::Revisions object. 

=head1 SYNOPSIS
  
  $pmwd = Parse::MediaWikiDump->new;
  $pages = $pmwd->pages('pages-articles.xml');
  $pages = $pmwd->pages(\*FILEHANDLE);
  
  #print the title and id of each article inside the dump file
  while(defined($page = $pages->next)) {
    print "title '", $page->title, "' id ", $page->id, "\n";
  }

=head1 METHODS

=over 4

=item $pages->new

Open the specified MediaWiki dump file. If the single argument to this method
is a string it will be used as the path to the file to open. If the argument
is a reference to a filehandle the contents will be read from the filehandle as
specified. 

=item $pages->next

Returns an instance of the next available Parse::MediaWikiDump::page object or returns undef
if there are no more articles left.

=item $pages->sitename

Returns a plain text string that is the name of the MediaWiki instance.

=item $pages->base

Returns the URL to the instances main article in the form of a string.

=item $pages->generator

Returns a string containing 'MediaWiki' and a version number of the instance that dumped this file.
Example: 'MediaWiki 1.14alpha'

=item $pages->case

Returns a string describing the case sensitivity configured in the instance.

=item $pages->namespaces

Returns a reference to an array of references. Each reference is to another array with the first
item being the unique identifier of the namespace and the second element containing a string
that is the name of the namespace.

=item $pages->namespaces_names

Returns an array reference the array contains strings of all the namespaces each as an element. 

=item $pages->current_byte

Returns the number of bytes that has been processed so far

=item $pages->size

Returns the total size of the dump file in bytes. 

=back

=head2 Scan an article dump file for double redirects that exist in the most recent article revision

  #!/usr/bin/perl
  
  #progress information goes to STDERR, a list of double redirects found
  #goes to STDOUT
  
  binmode(STDOUT, ":utf8");
  binmode(STDERR, ":utf8");
  
  use strict;
  use warnings;
  use Parse::MediaWikiDump;
  
  my $file = shift(@ARGV);
  my $pmwd = Parse::MediaWikiDump->new;
  my $pages;
  my $page;
  my %redirs;
  my $artcount = 0;
  my $file_size;
  my $start = time;
  
  if (defined($file)) {
  	$file_size = (stat($file))[7];
  	$pages = $pmwd->pages($file);
  } else {
  	print STDERR "No file specified, using standard input\n";
  	$pages = $pmwd->pages(\*STDIN);
  }
  
  #the case of the first letter of titles is ignored - force this option
  #because the other values of the case setting are unknown
  die 'this program only supports the first-letter case setting' unless
  	$pages->case eq 'first-letter';
  
  print STDERR "Analyzing articles:\n";
  
  while(defined($page = $pages->next)) {
    update_ui() if ++$artcount % 500 == 0;
  
    #main namespace only
    next unless $page->namespace eq '';
    next unless defined($page->redirect);
  
    my $title = case_fixer($page->title);
    #create a list of redirects indexed by their original name
    $redirs{$title} = case_fixer($page->redirect);
  }
  
  my $redir_count = scalar(keys(%redirs));
  print STDERR "done; searching $redir_count redirects:\n";
  
  my $count = 0;
  
  #if a redirect location is also a key to the index we have a double redirect
  foreach my $key (keys(%redirs)) {
    my $redirect = $redirs{$key};
  
    if (defined($redirs{$redirect})) {
      print "$key\n";
      $count++;
    }
  }
  
  print STDERR "discovered $count double redirects\n";
  
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
  
  sub pretty_bytes {
    my $bytes = shift;
    my $pretty = int($bytes) . ' bytes';
  
    if (($bytes = $bytes / 1024) > 1) {
      $pretty = int($bytes) . ' kilobytes';
    }
  
    if (($bytes = $bytes / 1024) > 1) {
      $pretty = sprintf("%0.2f", $bytes) . ' megabytes';
    }
  
    if (($bytes = $bytes / 1024) > 1) {
      $pretty = sprintf("%0.4f", $bytes) . ' gigabytes';
    }
  
    return $pretty;
  }
  
  sub pretty_number {
    my $number = reverse(shift);
    $number =~ s/(...)/$1,/g;
    $number = reverse($number);
    $number =~ s/^,//;
  
    return $number;
  }
  
  sub update_ui {
    my $seconds = time - $start;
    my $bytes = $pages->current_byte;
  
    print STDERR "  ", pretty_number($artcount),  " articles; "; 
    print STDERR pretty_bytes($bytes), " processed; ";
  
    if (defined($file_size)) {
      my $percent = int($bytes / $file_size * 100);
  
      print STDERR "$percent% completed\n"; 
    } else {
      my $bytes_per_second = int($bytes / $seconds);
      print STDERR pretty_bytes($bytes_per_second), " per second\n";
    }
  }

