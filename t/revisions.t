#!perl -w

use Test::Simple tests => 94;
use strict;
use Parse::MediaWikiDump;

my $file = 't/revisions_test.xml';
my $fh;
my $revisions;
my $mode;

$mode = 'file';
test_all($file);

open($fh, $file) or die "could not open $file: $!";

$mode = 'handle';
test_all($fh);

sub test_all {
	$revisions = Parse::MediaWikiDump::Revisions->new(shift);

	test_siteinfo();
	
	test_one();
	test_two();
	test_three();
	test_four();
	
	ok(! defined($revisions->next));
}

sub test_siteinfo {
	
	ok($revisions->sitename eq 'Sitename Test Value');
	ok($revisions->base eq 'Base Test Value');
	ok($revisions->generator eq 'Generator Test Value');
	ok($revisions->case eq 'Case Test Value');
	ok($revisions->namespaces->[0]->[0] == -2);
	ok($revisions->namespaces_names->[0] eq 'Media');
	ok($revisions->current_byte != 0);
	
	if ($mode eq 'file') {
		ok($revisions->size == 2783);
	} elsif ($mode eq 'handle') {
		ok(! defined($revisions->size));
	} else {
		die "invalid test mode";
	}
}

#the first two tests check everything to make sure information
#is not leaking across pages due to accumulator errors. 
sub test_one {
	my $page = $revisions->next;
	my $text = $page->text;
	
	ok(defined($page));
			
	ok($page->title eq 'Talk:Title Test Value');
	ok($page->id == 1);
	ok($page->revision_id == 47084);
	ok($page->username eq 'Username Test Value 1');
	ok($page->userid == 1292);
	ok($page->timestamp eq '2005-07-09T18:41:10Z');
	ok($page->userid == 1292);
	ok($page->minor);
	ok($$text eq "Text Test Value 1\n");
	ok($page->namespace eq 'Talk');
	ok(! defined($page->redirect));
	ok(! defined($page->categories));
}

sub test_two {
	my $page = $revisions->next;
	my $text = $page->text;

	ok($page->title eq 'Title Test Value #2');
	ok($page->id == 2);
	ok($page->revision_id eq '47085');
	ok($page->username eq 'Username Test Value 2');
	ok($page->timestamp eq '2006-07-09T18:41:10Z');
	ok($page->userid == 12);
	ok(! $page->minor);
	ok($$text eq "#redirect : [[fooooo]]");
	ok($page->namespace eq '');
	ok($page->redirect eq 'fooooo');
	ok(! defined($page->categories));
}

sub test_three {
	my $page = $revisions->next;
	my $text = $page->text;

	ok(defined($page));
	ok($page->redirect eq 'fooooo');
	ok($page->title eq 'Title Test Value #2');
	ok($page->id == 2);
	ok($page->timestamp eq '2005-07-09T18:41:10Z');
	ok($page->username eq 'Username Test Value');
	ok($page->userid == 1292);
}

sub test_four {
	my $page = $revisions->next;
	my $text = $page->text;

	ok(defined($page));

	ok($page->id == 4);
	ok($page->timestamp eq '2005-07-09T18:41:10Z');
	ok($page->username eq 'Username Test Value');
	ok($page->userid == 1292);

	#test for bug 36255
	ok($page->namespace eq '');
	ok($page->title eq 'NotANameSpace:Bar');
}
