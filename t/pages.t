#!perl -w

use Test::Simple tests => 82;
use strict;
use Parse::MediaWikiDump;

my $file = 't/pages_test.xml';
my $fh;
my $pages;
my $mode;

$mode = 'file';
test_all($file);

open($fh, $file) or die "could not open $file: $!";

$mode = 'handle';
test_all($fh);

sub test_all {
	$pages = Parse::MediaWikiDump->pages(shift);

	test_one();
	test_two();
	test_three();
	test_four();

	ok(! defined($pages->next));
}

sub test_one {
	my $page = $pages->next;
	my $text = $page->text;

	ok(defined($page));

	ok($pages->sitename eq 'Sitename Test Value');
	ok($pages->base eq 'Base Test Value');
	ok($pages->generator eq 'Generator Test Value');
	ok($pages->case eq 'Case Test Value');
	ok($pages->namespaces->[0]->[0] == -2);
	ok($pages->namespaces_names->[0] eq 'Media');
	ok($pages->current_byte != 0);
	
	if ($mode eq 'file') {
		ok($pages->size == 2872);
	} elsif ($mode eq 'handle') {
		ok(! defined($pages->size))
	} else {
		die "invalid test mode";
	}
	
	
	ok($page->title eq 'Talk:Title Test Value');
	ok($page->id == 1);
	ok($page->timestamp eq '2005-07-09T18:41:10Z');
	ok($page->username eq 'Username Test Value');
	ok($page->userid == 1292);
	ok($$text eq "Text Test Value\n");
	ok($page->namespace eq 'Talk');
	ok(! defined($page->categories));
}

sub test_two {
	my $page = $pages->next;

	ok(defined($page));
	ok($page->redirect eq 'fooooo');
	ok($page->title eq 'Title Test Value #2');
	ok($page->id == 2);
	ok($page->timestamp eq '2005-07-09T18:41:10Z');
	ok($page->username eq 'Username Test Value');
	ok($page->userid == 1292);
	ok(! defined($page->categories));
}

sub test_three {
	my $page = $pages->next;

	ok(defined($page));
	ok($page->redirect eq 'fooooo');
	ok($page->title eq 'Title Test Value #3');
	ok($page->id == 3);
	ok($page->timestamp eq '2005-07-09T18:41:10Z');
	ok($page->username eq 'Username Test Value');
	ok($page->userid == 1292);
	ok(! defined($page->categories));
}

sub test_four {
	my $page = $pages->next;

	ok(defined($page));

	ok($page->id == 4);
	ok($page->timestamp eq '2005-07-09T18:41:10Z');
	ok($page->username eq 'Username Test Value');
	ok($page->userid == 1292);

	#test for bug 36255
	ok($page->namespace eq '');
	ok($page->title eq 'NotANameSpace:Bar');
}
