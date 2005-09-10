our $VERSION = '0.2';
#the POD is at the end of this file
#avoid shift - it is computationally more expensive than pop
#and shifting values for subroutine input should be avoided in
#any subroutines that get called often, like the handlers

package Parse::MediaWikiDump::Pages;

use strict;
use warnings;
use XML::Parser;

use constant T_START => 1;
use constant T_END => 2;
use constant T_TEXT => 3;

sub new {
	my $class = shift;
	my $source = shift;
	my $self = {};

	bless($self, $class);

	$$self{PARSER} = XML::Parser->new;
	$$self{PARSER}->setHandlers('Start', \&start_handler,
				    'End', \&end_handler,
				    'Char', \&char_handler);
        $$self{EXPAT} = $$self{PARSER}->parse_start(state => $self);
	$$self{BUFFER} = []; 
	$$self{CHUNK_SIZE} = 32768;
	$$self{BUF_LIMIT} = 10000;

	$self->open($source);
	$self->init;

	return $self;
}

sub page {
	my $self = shift;
	my $buffer = $$self{BUFFER};
	my $offset;
	my @page;

	while(1) {
		$offset = $self->search_buffer([T_END, 'page']);
		last if $offset != -1;
		return undef unless $self->parse_more;
	}

	@page = splice(@$buffer, 0, $offset + 1);

	if (! token_compare($page[0], [T_START, 'page'])) {
		$self->dump($buffer);
		die "expected <page>; got " . token2text($page[0]);
	}

	my $data = $self->parse_page(\@page);

	return Parse::MediaWikiDump::page->new($data);
}

sub current_byte {
	my $self = shift;
#	my $bytes = $$self{EXPAT}->current_byte;

	return(sprintf("%d", $$self{EXPAT}->current_byte));
}

sub dump {
	my $self = shift;
	my $buffer = shift || $$self{BUFFER};
	my $offset = 0;

	foreach my $i (0 .. $#$buffer) {
		my $token = $$buffer[$i];

		print STDERR "$i ";

		if ($$token[0] == T_START) {
			my $attr = $$token[2];
			print STDERR "  " x $offset;
			print STDERR "START $$token[1] ";

			foreach my $key (sort(keys(%$attr))) {
				print STDERR "$key=\"$$attr{$key}\" ";
			}

			print STDERR "\n";
			$offset++;
		} elsif ($$token[0] == T_END) {
			$offset--;
			print STDERR "  " x $offset;
			print STDERR "END $$token[1]\n";
		} elsif ($$token[0] == T_TEXT) {
			my $ref = $$token[1];
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
	my $self = shift;
	return $$self{HEAD}{sitename};
}

sub base {
	my $self = shift;
	return $$self{HEAD}{base};
}

sub generator {
	my $self = shift;
	return $$self{HEAD}{generator};
}

sub case {
	my $self = shift;
	return $$self{HEAD}{case};
}

sub namespaces {
	my $self = shift;
	return $$self{HEAD}{namespaces};
}
#private functions with OO interface
sub open {
	my $self = shift;
	my $source = shift;

	if (scalar($source) eq 'GLOB') {
		$$self{SOURCE} = $source;
	} elsif (! open($$self{SOURCE}, $source)) {
		die "could not open $source: $!";
	}

	return 1;
}

sub init {
	my $self = shift;
	my $offset;
	my @head;

	while(1) {
		die "could not init" unless $self->parse_more;

		$offset = $self->search_buffer([T_END, 'siteinfo']);

		last if $offset != -1;
	}

	@head = splice(@{$$self{BUFFER}}, 0, $offset + 1);

	$self->parse_head(\@head);

	return 1;
}

sub parse_more {
	my ($self) = @_;
	my $buf;

	my $ret = read($$self{SOURCE}, $buf, $$self{CHUNK_SIZE});

	if ($ret == 0) {
		$$self{FINISHED} = 1;
		$$self{EXPAT}->parse_done();
		return 0;
	} elsif (! defined($ret)) {
		die "error during read: $!";
	}

	$$self{EXPAT}->parse_more($buf);

	my $buflen = scalar(@{$$self{BUFFER}});

	die "buffer length of $buflen exceeds $$self{BUF_LIMIT}" unless
		$buflen < $$self{BUF_LIMIT};

	return 1;
}

sub search_buffer {
	my ($self, $search, $list) = @_;

	$list = $$self{BUFFER} unless defined $list;

	return -1 if scalar(@$list) == 0;

	foreach my $i (0 .. $#$list) {
		return $i if token_compare($$list[$i], $search);
	}

	return -1;
}

#this function is very frightning =)
sub parse_head {
	my $self = shift;
	my $buffer = shift;
	my $state = 'start';
	my %data = (namespaces => []);

	for (my $i = 0; $i <= $#$buffer; $i++) {
		my $token = $$buffer[$i];

		if ($state eq 'start') {
			my $version;
			die "$i: expected <mediawiki> got " . token2text($token) unless
				token_compare($token, [T_START, 'mediawiki']);

			die "$i: version is a required attribute" unless
				defined($version = $$token[2]->{version});

			die "$i: version $version unsupported" unless $version eq '0.3';

			$token = $$buffer[++$i];

			die "$i: expected <siteinfo> got " . token2text($token) unless
				token_compare($token, [T_START, 'siteinfo']);

			$state = 'in_siteinfo';
		} elsif ($state eq 'in_siteinfo') {
			if (token_compare($token, [T_START, 'namespaces'])) {
				$state = 'in_namespaces';
				next;
			} elsif (token_compare($token, [T_END, 'siteinfo'])) {
				last;
			} elsif (token_compare($token, [T_START, 'sitename'])) {
				$token = $$buffer[++$i];

				if ($$token[0] != T_TEXT) {
					die "$i: expected TEXT but got " . token2text($token);
				}

				$data{sitename} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'sitename'])) {
					die "$i: expected </sitename> but got " . token2text($token);
				}
			} elsif (token_compare($token, [T_START, 'base'])) {
				$token = $$buffer[++$i];

				if ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected TEXT but got " . token2text($token);
				}

				$data{base} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'base'])) {
					$self->dump($buffer);
					die "$i: expected </base> but got " . token2text($token);
				}

			} elsif (token_compare($token, [T_START, 'generator'])) {
				$token = $$buffer[++$i];

				if ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected TEXT but got " . token2text($token);
				}

				$data{generator} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'generator'])) {
					$self->dump($buffer);
					die "$i: expected </generator> but got " . token2text($token);
				}

			} elsif (token_compare($token, [T_START, 'case'])) {
				$token = $$buffer[++$i];

				if ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected </case> but got " . token2text($token);
				}

				$data{case} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'case'])) {
					$self->dump($buffer);
					die "$i: expected </case> but got " . token2text($token);
				}
			}

		} elsif ($state eq 'in_namespaces') {
			my $key;
			my $name;

			if (token_compare($token, [T_END, 'namespaces'])) {
				$state = 'in_siteinfo';
				next;
			} 

			if (! token_compare($token, [T_START, 'namespace'])) {
				die "$i: expected <namespace> or </namespaces>; got " . token2text($token);
			}

			die "$i: key is a required attribute" unless
				defined($key = $$token[2]->{key});

			$token = $$buffer[++$i];

			#the default namespace has no text associated with it
			if ($$token[0] == T_TEXT) {
				$name = ${$$token[1]};
			} elsif (token_compare($token, [T_END, 'namespace'])) {
				$name = '';
				$i--; #move back one for below
			} else {
				die "$i: should never happen";	
			}

			push(@{$data{namespaces}}, [$key, $name]);

			$token = $$buffer[++$i];

			if (! token_compare($token, [T_END, 'namespace'])) {
				$self->dump($buffer);
				die "$i: expected </namespace> but got " . token2text($token);
			}

		} else {
			die "$i: unknown state '$state'";
		}
	}

	$$self{HEAD} = \%data;
}

sub parse_page {
	my $self = shift;
	my $buffer = shift;
	my %data;
	my $state = 'start';

	for (my $i = 0; $i <= $#$buffer; $i++) {
		my $token = $$buffer[$i];

		if ($state eq 'start') {
			if (! token_compare($token, [T_START, 'page'])) {
				$self->dump($buffer);
				die "$i: expected <page>; got " . token2text($token);
			}

			$state = 'in_page';
		} elsif ($state eq 'in_page') {
			if (token_compare($token, [T_START, 'revision'])) {
				$state = 'in_revision';
				next;
			} elsif (token_compare($token, [T_END, 'page'])) {
				last;
			} elsif (token_compare($token, [T_START, 'title'])) {
				$token = $$buffer[++$i];

				if (token_compare($token, [T_END, 'title'])) {
					$data{title} = '';
					next;
				}

				if ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{title} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'title'])) {
					$self->dump($buffer);
					die "$i: expected </title>; got " . token2text($token);
				}
			} elsif (token_compare($token, [T_START, 'id'])) {
				$token = $$buffer[++$i];
	
				if ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{id} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'id'])) {
					$self->dump($buffer);
					die "$i: expected </id>; got " . token2text($token);
				}
			}
		} elsif ($state eq 'in_revision') {
			if (token_compare($token, [T_END, 'revision'])) {
				$state = 'in_page';
				next;	
			} elsif (token_compare($token, [T_START, 'contributor'])) {
				$state = 'in_contributor';
				next;
			} elsif (token_compare($token, [T_START, 'id'])) {
				$token = $$buffer[++$i];
	
				if ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{revision_id} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'id'])) {
					$self->dump($buffer);
					die "$i: expected </id>; got " . token2text($token);
				}

			} elsif (token_compare($token, [T_START, 'timestamp'])) {
				$token = $$buffer[++$i];

				if ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{timestamp} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'timestamp'])) {
					$self->dump($buffer);
					die "$i: expected </timestamp>; got " . token2text($token);
				}
			} elsif (token_compare($token, [T_START, 'minor'])) {
				$data{minor} = 1;
				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'minor'])) {
					$self->dump($buffer);
					die "$i: expected </minor>; got " . token2text($token);
				}
			} elsif (token_compare($token, [T_START, 'comment'])) {
				$token = $$buffer[++$i];

				#account for possible null-text 
				if (token_compare($token, [T_END, 'comment'])) {
					$data{comment} = '';
					next;
				}

				if ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{comment} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'comment'])) {
					$self->dump($buffer);
					die "$i: expected </comment>; got " . token2text($token);
				}

			} elsif (token_compare($token, [T_START, 'text'])) {
				my $token = $$buffer[++$i];

				if (token_compare($token, [T_END, 'text'])) {
					${$data{text}} = '';
					next;
				} elsif ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{text} = $$token[1];

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'text'])) {
					$self->dump($buffer);
					die "$i: expected </text>; got " . token2text($token);
				}
			
			}

		} elsif ($state eq 'in_contributor') {
			if (token_compare($token, [T_END, 'contributor'])) {
				$state = 'in_revision';
				next;
			} elsif (token_compare($token, [T_START, 'username'])) {
				$token = $$buffer[++$i];

				if ($$token[0] != T_TEXT) {
					$self->dump($buffer);
					die "$i: expected TEXT; got " . token2text($token);
				}

				$data{username} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'username'])) {
					$self->dump($buffer);
					die "$i: expected </username>; got " . token2text($token);
				}
			} elsif (token_compare($token, [T_START, 'id'])) {
				$token = $$buffer[++$i];
				
				if ($$token[0] != T_TEXT) {
					$self->dump;
					die "$i: expecting TEXT; got " . token2text($token);
				}

				$data{userid} = ${$$token[1]};

				$token = $$buffer[++$i];

				if (! token_compare($token, [T_END, 'id'])) {
					$self->dump($buffer);
					die "$i: expecting </id>; got " . token2text($token);
				}
			}
		} else {
			die "unknown state: $state";
		}
	}

	$data{minor} = 0 unless defined($data{minor});

	return \%data;
}

#private functions with out OO interface
sub token2text {
	my $token = shift;

	if ($$token[0] == T_START) {
		return "<$$token[1]>";
	} elsif ($$token[0] == T_END) {
		return "</$$token[1]>";
	} elsif ($$token[0] == T_TEXT) {
		return "!text_token!";	
	} else {
		return "!unknown!";
	}
}

sub token_compare {
	my ($toke1, $toke2) = @_;

	foreach my $i (0 .. $#$toke2) {
		if ($$toke1[$i] ne $$toke2[$i]) {
			return 0;
		}
	}

	return 1;
}

sub start_handler {
	my ($p, $tag, %atts) = @_;	
	my $self = $p->{state};

	push(@{$$self{BUFFER}}, [T_START, $tag, \%atts]);

	return 1;
}

sub end_handler {
	my ($p, $tag) = @_;
	my $self = $p->{state};

	push(@{$$self{BUFFER}}, [T_END, $tag]);

	return 1;
}

sub char_handler {
	my ($p, $chars) = @_;
	my $self = $p->{state};
	my $buffer = $$self{BUFFER};
	my $curent = $$buffer[$#$buffer];

	if (! defined($curent)) {
 		#skip any text not inside a container
		return 1;
	} elsif ($$curent[0] == T_TEXT) {
		${$$curent[1]} .= $chars;
	} elsif ($$curent[0] == T_START) {
		my $ignore_ws_only = 1;

		if (defined($$curent[2]->{'xml:space'}) &&
			($$curent[2]->{'xml:space'} eq 'preserve')) {
				$ignore_ws_only = 0;
		}

		if ($ignore_ws_only) {
			return 1 if $chars =~ m/^\s+$/m;
		}

		push(@$buffer, [T_TEXT, \$chars]);
	} 

	return 1;
}

package Parse::MediaWikiDump::page;

use strict;
use warnings;

sub new {
	my $class = shift;
	my $data = shift;
	my $self = {};

	bless($self, $class);

	$$self{DATA} = $data;
	$$self{CACHE} = {};

	return $self;
}

sub namespace {
	my $self = shift;

	return $$self{CACHE}{namespace} if defined($$self{CACHE}{namespace});

	my $title = $$self{DATA}{title};

	if ($title =~ m/^([^:]+)\:/) {
		$$self{CACHE}{namespace} = $1;
		return $1;
	} else {
		$$self{CACHE}{namespace} = '';
		return '';
	}
}

sub categories {
	my $self = shift;

	return $$self{CACHE}{categories} if defined($$self{CACHE}{categories});

	my $text = $$self{DATA}{text};
	my @cats;
	
	while($$text =~ m/\[\[category:\s*([^\]]+)\]\]/gi) {
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
	my $self = shift;
	my $text = $$self{DATA}{text};

	return $$self{CACHE}{redirect} if exists($$self{CACHE}{redirect});

	if ($$text =~ m/^#redirect\s*\[\[([^\]]*)\]\]/i) {
		$$self{CACHE}{redirect} = $1;
		return $1;
	} else {
		$$self{CACHE}{redirect} = undef;
		return undef;
	}
}

sub title {
	my $self = shift;
	return $$self{DATA}{title};
}

sub id {
	my $self = shift;
	return $$self{DATA}{id};
}

sub revision_id {
	my $self = shift;
	return $$self{DATA}{revision_id};
}

sub timestamp {
	my $self = shift;
	return $$self{DATA}{timestamp};
}

sub username {
	my $self = shift;
	return $$self{DATA}{username};
}

sub userid {
	my $self = shift;
	return $$self{DATA}{userid};
}

sub minor {
	my $self = shift;
	return $$self{DATA}{minor};
}

sub text {
	my $self = shift;
	return $$self{DATA}{text};
}

package Parse::MediaWikiDump::Links;

use strict;
use warnings;

sub new {
	my $class = shift;
	my $source = shift;
	my $self = {};
	$$self{BUFFER} = [];

	bless($self, $class);

	$self->open($source);
	$self->init;

	return $self;
}

sub link {
	my $self = shift;
	my $buffer = $$self{BUFFER};
	my $link;

	while(1) {
		if (defined($link = pop(@$buffer))) {
			last;
		}

		#signals end of input
		return undef unless $self->parse_more;
	}

	return Parse::MediaWikiDump::link->new($link);
}

#private functions with OO interface
sub parse_more {
	my $self = shift;
	my $source = $$self{SOURCE};
	my $need_data = 1;
	
	while($need_data) {
		my $line = <$source>;

		last unless defined($line);

		while($line =~ m/\((\d+),(\d+)\)[;,]/g) {
			push(@{$$self{BUFFER}}, [$1, $2]);
			$need_data = 0;
		}
	}

	#if we still need data and we are here it means we ran out of input
	if ($need_data) {
		return 0;
	}
	
	return 1;
}

sub open {
	my $self = shift;
	my $source = shift;

	if (scalar($source) ne 'GLOB') {
		die "could not open $source: $!" unless
			open($$self{SOURCE}, $source);
	} else {
		$$self{SOURCE} = $source;
	}

	return 1;
}

sub init {
	my $self = shift;
	my $source = $$self{SOURCE};
	my $found = 0;
	
	while(<$source>) {
		if (m/^LOCK TABLES `links` WRITE;/) {
			$found = 1;
			last;
		}
	}

	die "not a Mediawiki link dump file" unless $found;
}

package Parse::MediaWikiDump::link;

#you must pass in a fully populated link array reference
sub new {
	my $class = shift;
	my $self = shift;

	bless($self, $class);

	return $self;
}

sub from {
	my $self = shift;

	return $$self[0];
}

sub to {
	my $self = shift;

	return $$self[1];
}

1;

__END__

=head1 NAME

Parse::MediaWikiDump - Tools to process Mediawiki dump files

=head1 SYNOPSIS

  use Parse::MediaWikiDump;

  $source = '20050713_pages.xml';
  $source = \*FILEHANDLE;
  $source = shift(@ARGV);

  $pages = Parse::MediaWikiDump::Pages->new($source);
  $links = Parse::MediaWikiDump::Links->new($source);

  #get one record from the dump file
  $page = $pages->page;
  $link = $links->link;

  #information about the page dump file
  $pages->sitename;
  $pages->base;
  $pages->generator;
  $pages->case;
  $pages->namespaces;

  #information about a page record
  $page->redirect;
  $page->categories;
  $page->title;
  $page->id;
  $page->revision_id;
  $page->timestamp;
  $page->username;
  $page->userid;
  $page->minor;
  $page->text;

  #information about a link
  $link->from;
  $link->to;

=head1 DESCRIPTION

This module provides the tools needed to process the contents of various 
Mediawiki dump files. 

=head1 USAGE

To use this module you must create an instance of a parser for the type of
dump file you are trying to parse. The current parsers are:

=over 4

=item Parse::MediaWikiDump::Pages

Parse the contents of the page archive.

=item Parse::MediaWikiDump::Links

Parse the link list dump file. *WARNING* The probability of this dump
file existing after the dumpfile format change is unknown. As of this writing
there is no links dump file to match the current page dump file but this 
class is able to parse the available dump files. 

=back

=head2 General

Both parsers require an argument to new that is a location of source data
to parse; this argument can be either a filename or a reference to an already
open filehandle. This entire software suite will die() upon errors in the file,
inconsistencies on the stack, etc. If this concerns you then you can wrap
the portion of your code that uses these calls with eval().

=head2 Parse::MediaWikiDump::Pages

It is possible to create a Parse::MediaWikiDump::Pages object two ways:

=over 4

=item $pages = Parse::MediaWikiDump::Pages->new($filename);

=item $pages = Parse::MediaWikiDump::Pages->new(\*FH);

=back

After creation the folowing methods are avalable:

=over 4

=item $pages->page

Returns the next available record from the dump file if it is available,
otherwise returns undef. Records returned are instances of 
Parse::MediaWikiDump::page; see below for information on those objects.

=item $pages->sitename

Returns the plain-text name of the instance the dump is from.

=item $pages->base

Returns the base url to the website of the instance.

=item $pages->generator

Returns the version of the software that generated the file.

=item $pages->case

Returns the case-sensitivity configuration of the instance.

=item $pages->namespaces

Returns an array reference to the list of namespaces in the instance. Each
namespace is stored as an array reference which has two items; the first is the
namespace number and the second is the namespace name. In the case of namespace
0 the text stored for the name is ''

=back

=head3 Parse::MediaWikiDump::page

The Parse::MediaWikiDump::page object represents a distinct Mediawiki page, 
article, module, what have you. These objects are returned by the page method
of a Parse::MediaWikiDump::Pages instance. The scalar returned is a reference
to a hash that contains all the data of the page in a straightforward manor. 
While it is possible to access this hash directly, and it involves less overhead
than using the methods below, it is beyond the scope of the interface and is
undocumented. 

Some of the methods below require additional processing, such as namespaces,
redirect, and categories, to name a few. In these cases the returned result
is cached and stored inside the object so the processing does not have to be
redone. This is transparent to you; just know that you don't have to worry about
optimizing calls to these functions to limit processing overhead. 

The following methods are available:

=over 4

=item $page->id

=item $page->title

=item $page->text

A reference to a scalar containing the plaintext of the page.

=item $page->redirect

The plain text name of the article redirected to or undef if the page is not
a redirect.

=item $page->categories

Returns a reference to an array that contains a list of categories or undef
if there are no categories.

=item $page->revision_id

=item $page->timestamp

=item $page->username

=item $page->userid

=item $page->minor

=back

=head2 Parse::MediaWikiDump::Links

This module also takes either a filename or a reference to an already open 
filehandle. For example:

  $links = Parse::MediaWikiDump::Links->new($filename);
  $links = Parse::MediaWikiDump::Links->new(\*FH);

It is then possible to extract the links a single link at a time using the
->link method, which returns an instance of Parse::MediaWikiDump::link or undef
when there is no more data. For instance: 

  while(defined($link = $links->link)) {
    print 'from ', $link->from, ' to ', $link->to, "\n";
  }

=head3 Parse::MediaWikiDump::link

Instances of this class are returned by the link method of a 
Parse::MediaWikiDump::Links instance. The following methods are available:

=over 4

=item $link->from

=item $link->to

=back

These methods extract the numerical id of the article that is linked from and 
to. It is possible to extract the values from the underlying data structure 
(instead of using the object methods). While this can yield a speed increase
it is not a part of the standard interface so it is undocumented.

=head1 EXAMPLES

=head2 Find uncategorized articles in the main name space

  #!/usr/bin/perl -w
  
  use strict;
  use Parse::MediaWikiDump;

  my $file = shift(@ARGV) or die "must specify a Mediawiki dump file";
  my $pages = Parse::MediaWikiDump::Pages->new($file);
  my $page;

  while(defined($page = $pages->page)) {
    #main namespace only           
    next unless $page->namespace eq '';

    print $page->title, "\n" unless defined($page->categories);
  }

=head2 Find double redirects in the main name space

  #!/usr/bin/perl -w

  use strict;
  use Parse::MediaWikiDump;

  my $file = shift(@ARGV) or die "must specify a Mediawiki dump file";
  my $pages = Parse::MediaWikiDump::Pages->new($file);
  my $page;
  my %redirs;

  while(defined($page = $pages->page)) {
    next unless $page->namespace eq '';
    next unless defined($page->redirect);

    my $title = $page->title;

    $redirs{$title} = $page->redirect;
  }

  foreach my $key (keys(%redirs)) {
    my $redirect = $redirs{$key};
    if (defined($redirs{$redirect})) {
      print "$key\n";
    }
  }

=head2 Find the stub with the most links to it

  #!/usr/bin/perl -w
  
  use strict;
  use Parse::MediaWikiDump;
  
  my $pages = Parse::MediaWikiDump::Pages->new(shift(@ARGV));
  my $links = Parse::MediaWikiDump::Links->new(shift(@ARGV));
  my %stubs;
  my $page;
  my $link;
  my @list;
  
  select(STDERR);
  $| = 1;
  print '';
  select(STDOUT);
  
  print STDERR "Locating stubs: ";
  
  while(defined($page = $pages->page)) {
  	next unless $page->namespace eq '';
  
  	my $text = $page->text;
  
  	next unless $$text =~ m/stub}}/i;
  
  	my $title = $page->title;
  	my $id = $page->id;
  
  	$stubs{$id} = [$title, 0];
  }
  
  print STDERR scalar(keys(%stubs)), " stubs found\n";
  
  print STDERR "Processing links: ";
  
  while(defined($link = $links->link)) {
  	my $to = $link->to;
  
  	next unless defined($stubs{$to});
  
  	$stubs{$to}->[1]++;
  }
  
  print STDERR "done\n";
  
  while(my ($key, $val) = each(%stubs)) {
  	push(@list, $val);
  }
  
  @list = sort({ $$b[1] <=> $$a[1]} @list);
  
  my $stub = $list[0]->[0];
  my $num_links = $list[0]->[1];
  
  print "Most wanted stub: $stub with $num_links links\n";

=head1 TODO

=over 4

=item Optomization 

It would be nice to increase the processing speed of the XML files but short of
an implementation using XS I'm not sure what to do. 

=item Testing

This software has received only light testing consisting of multiple runs over
the most recent English Wikipedia dump file: July 13, 2005. 

=back

=head1 AUTHOR

This module was created and documented by Tyler Riddle E<lt>triddle@gmail.orgE<gt>. 

=head1 BUGS

Please report any bugs or feature requests to
C<bug-parse-mediawikidump@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Parse-MediaWikiDump>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2005 Tyler Riddle, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

