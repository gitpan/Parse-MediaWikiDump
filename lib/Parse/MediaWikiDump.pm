package Parse::MediaWikiDump;
our $VERSION = '0.91';

use 5.8.8;

use Parse::MediaWikiDump::XML;
use Parse::MediaWikiDump::Revisions;
use Parse::MediaWikiDump::Pages;
use Parse::MediaWikiDump::page;
use Parse::MediaWikiDump::Links;
use Parse::MediaWikiDump::link;
use Parse::MediaWikiDump::CategoryLinks;
use Parse::MediaWikiDump::category_link;

#the POD is at the end of this file



#package Parse::MediaWikiDump::ExternalLinks;
#
#use strict;
#use warnings;
#
#sub new {
#	my ($class, $source) = @_;
#	my $self = {};
#
#	$$self{BUFFER} = [];
#	$$self{BYTE} = 0;
#
#	bless($self, $class);
#
#	$self->open($source);
#	$self->init;
#
#	return $self;
#}
#
#sub next {
#	my ($self) = @_;
#	my $buffer = $$self{BUFFER};
#	my $link;
#
#	while(1) {
#		if (defined($link = pop(@$buffer))) {
#			last;
#		}
#
#		#signals end of input
#		return undef unless $self->parse_more;
#	}
#
#	return Parse::MediaWikiDump::external_link->new($link);
#}
#
##private functions with OO interface
#sub parse_more {
#	my ($self) = @_;
#	my $source = $$self{SOURCE};
#	my $need_data = 1;
#	
#	while($need_data) {
#		my $line = <$source>;
#
#		last unless defined($line);
#
#		$$self{BYTE} += length($line);
#
#		while($line =~ m/\((\d+),'(.*?)','(.*?)'\)[;,]/g) {
#			push(@{$$self{BUFFER}}, [$1, $2, $3]);
#			$need_data = 0;
#		}
#	}
#
#	#if we still need data and we are here it means we ran out of input
#	if ($need_data) {
#		return 0;
#	}
#	
#	return 1;
#}
#
#sub open {
#	my ($self, $source) = @_;
#
#	if (ref($source) ne 'GLOB') {
#		die "could not open $source: $!" unless
#			open($$self{SOURCE}, $source);
#
#		$$self{SOURCE_FILE} = $source;
#	} else {
#		$$self{SOURCE} = $source;
#	}
#
#	binmode($$self{SOURCE}, ':utf8');
#
#	return 1;
#}
#
#sub init {
#	my ($self) = @_;
#	my $source = $$self{SOURCE};
#	my $found = 0;
#	
#	while(<$source>) {
#		if (m/^LOCK TABLES `externallinks` WRITE;/) {
#			$found = 1;
#			last;
#		}
#	}
#
#	die "not a MediaWiki link dump file" unless $found;
#}
#
#sub current_byte {
#	my ($self) = @_;
#
#	return $$self{BYTE};
#}
#
#sub size {
#	my ($self) = @_;
#	
#	return undef unless defined $$self{SOURCE_FILE};
#
#	my @stat = stat($$self{SOURCE_FILE});
#
#	return $stat[7];
#}
#
#package Parse::MediaWikiDump::external_link;
#
##you must pass in a fully populated link array reference
#sub new {
#	my ($class, $self) = @_;
#
#	bless($self, $class);
#
#	return $self;
#}
#
#sub from {
#	my ($self) = @_;
#	return $$self[0];
#}
#
#sub to {
#	my ($self) = @_;
#	return $$self[1];
#}
#
#sub index {
#	my ($self) = @_;
#	return $$self[2];
#}
#
#sub timestamp {
#	my ($self) = @_;
#	return $$self[3];
#


1;

__END__

=head1 NAME

Parse::MediaWikiDump - Tools to process MediaWiki dump files

=head1 SYNOPSIS

  use Parse::MediaWikiDump;

  #for XML article dump files with only one revision per
  #article
  $pages = Parse::MediaWikiDump::Pages->new('pages-articles.xml');
  $pages = Parse::MediaWikiDump::Pages->new(\*FILEHANDLE);
  
  #For XML article dump files that have more than one
  #revision per article - behaves exactly like
  #Parse::MediaWikiDump::Pages
  $revisions = Parse::MediaWikiDump::Revisions->new('pages-all-revisions.xml');
  $revisions = Parse::MediaWikiDump::Revisions->new(\*FILEHANDLE);
  
  #for SQL link dump files
  $links = Parse::MediaWikiDump::Links->new('links.sql');
  $links = Parse::MediaWikiDump::Links->new(\*FILEHANDLE);

  #get all the records from the dump files, one record at a time
  
  while(defined($page = $pages->next)) {
    print "title '", $page->title, "' id ", $page->id, "\n";
  }

  while(defined($page = $revisions->next)) {
    print "title '", $page->title, "' id ", $page->id, "\n";
  }

  while(defined($link = $links->next)) {
    print "link from ", $link->from, " to ", $link->to, "\n";
  }

  #information about the page dump files
  $pages->sitename;
  $pages->base;
  $pages->generator;
  $pages->case;
  $pages->namespaces;
  $pages->namespaces_names;
  $pages->current_byte;
  $pages->size;
  
  $revisions->sitename;
  $revisions->base;
  $revisions->generator;
  $revisions->case;
  $revisions->namespaces;
  $revisions->namespaces_names;
  $revisions->current_byte;
  $revisions->size;
  
  #information about a page record
  $page->redirect;
  $page->categories;
  $page->title;
  $page->namespace;
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
  $link->namespace;

=head1 DESCRIPTION

This module provides the tools needed to process the contents of the XML page 
dump files and the SQL based links dump file.

=head1 USAGE

To use this module you must create an instance of a parser for the type of
dump file you are trying to parse. The current parsers are:

=over 4

=item Parse::MediaWikiDump::Pages

Parse the contents of the page archive.

=item Parse::MediaWikiDump::Revisions

Parse the contents of a page dump with more than one revision per article.

=item Parse::MediaWikiDump::Links

Parse the contents of the links dump file. 

=back

=head2 General

All parsers require an argument to new that is a location of source data
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

=item $pages->next

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
0 the text stored for the name is ''.

=item $pages->namespaces_names

Returns an array reference to a list of namspace names only; this is a single
dimensional array with plain text string values.

=item $pages->current_byte

Returns the number of bytes parsed so far.

=item $pages->size

Returns the size of the dump file in bytes.

=back

=head4 Upgrade Path

The Parse::MediaWikiDump::Pages object is being replaced with a new implementation 
that is fully backwards compatible. The new implementation now supports multiple
revisions for a single page. Both implementations return the same Parse::MediaWikiDump::page
object and that interface is not changing. The new implementation is called 
Parse::MediaWikiDump::Revisions and in the future Parse::MediaWikiDump::Pages
will be a special case of Parse::MediaWikiDump::Revisions that will enforce
only a single revision per page. 

The upgrade process will not require any API or object behavior changes however
the new implementation needs to be tested. Because Parse::MediaWikiDump::Revisions
is fully backwards compatible with Parse::MediaWikiDump::Pages it is possible to
use the new implementation as a drop in replacement for testing. Please report
success and failures for Parse::MediaWikiDump::Revisions to the author contact
at the end of this documentation. 

=head3 Parse::MediaWikiDump::page

The Parse::MediaWikiDump::page object represents a distinct MediaWiki page, 
article, module, what have you. These objects are returned by the next() method
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

=item $page->namespace

Returns an empty string (such as '') for the main namespace or a string 
containing the name of the namespace.

=item $page->text

A reference to a scalar containing the plaintext of the page.

=item $page->redirect

The plain text name of the article redirected to or undef if the page is not
a redirect.

=item $page->categories

Returns a reference to an array that contains a list of categories or undef
if there are no categories. This method does not understand templates and may
not return all the categories the article actually belongs in. 

=item $page->revision_id

=item $page->timestamp

=item $page->username

=item $page->userid

=item $page->minor

=back

=head2 Parse::MediaWikiDump::Revisions

This parser is for the dump files that contain all the revision history information for a single 
page. It works in an identical manner as Parse::MediaWikiDump::Pages including returning an 
instance of Parse::MediaWikiDump::page. See the documentation for the previous two objects for
details on how to use Parse::MediaWikiDump::Revisions. 

=head2 Parse::MediaWikiDump::Links

This module also takes either a filename or a reference to an already open 
filehandle. For example:

  $links = Parse::MediaWikiDump::Links->new($filename);
  $links = Parse::MediaWikiDump::Links->new(\*FH);

It is then possible to extract the links a single link at a time using the
next method, which returns an instance of Parse::MediaWikiDump::link or undef
when there is no more data. For instance: 

  while(defined($link = $links->next)) {
    print 'from ', $link->from, ' to ', $link->to, "\n";
  }

=head3 Parse::MediaWikiDump::link

Instances of this class are returned by the link method of a 
Parse::MediaWikiDump::Links instance. The following methods are available:

=over 4

=item $link->from

The numerical id the link was in. 

=item $link->to

The plain text name the link is to, minus the namespace.

=item $link->namespace

The numerical id of the namespace the link points to. 

=back

=head1 EXAMPLES

=head2 Extract the article text for a given title

  #!/usr/bin/perl
  
  use strict;
  use warnings;
  use Parse::MediaWikiDump;
  
  my $file = shift(@ARGV) or die "must specify a MediaWiki dump of the current pages";
  my $title = shift(@ARGV) or die "must specify an article title";
  my $dump = Parse::MediaWikiDump::Pages->new($file);
  
  binmode(STDOUT, ':utf8');
  binmode(STDERR, ':utf8');
  
  #this is the only currently known value but there could be more in the future
  if ($dump->case ne 'first-letter') {
    die "unable to handle any case setting besides 'first-letter'";
  }
  
  $title = case_fixer($title);
  
  while(my $page = $dump->next) {
    if ($page->title eq $title) {
      print STDERR "Located text for $title\n";
      my $text = $page->text;
      print $$text;
      exit 0;
    }
  }
  
  print STDERR "Unable to find article text for $title\n";
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

=head2 Scan the dump file for double redirects

  #!/usr/bin/perl
  
  #progress information goes to STDERR, a list of double redirects found
  #goes to STDOUT
  
  binmode(STDOUT, ":utf8");
  binmode(STDERR, ":utf8");
  
  use strict;
  use warnings;
  use Parse::MediaWikiDump;
  
  my $file = shift(@ARGV);
  my $pages;
  my $page;
  my %redirs;
  my $artcount = 0;
  my $file_size;
  my $start = time;
  
  if (defined($file)) {
  	$file_size = (stat($file))[7];
  	$pages = Parse::MediaWikiDump::Pages->new($file);
  } else {
  	print STDERR "No file specified, using standard input\n";
  	$pages = Parse::MediaWikiDump::Pages->new(\*STDIN);
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

=head1 AUTHOR

This module was created, documented, and is maintained by 
Tyler Riddle E<lt>triddle@gmail.comE<gt>. 

Fix for bug 36255 "Parse::MediaWikiDump::page::namespace may return a string
which is not really a namespace" provided by Amir E. Aharoni.

=head1 BUGS

Please report any bugs or feature requests to
C<bug-parse-mediawikidump@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Parse-MediaWikiDump>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head2 Known Bugs

No known bugs at this time. 

=head1 COPYRIGHT & LICENSE

Copyright 2005 Tyler Riddle, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

