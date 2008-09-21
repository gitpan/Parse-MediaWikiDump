#!perl -w

use Test::Simple tests => 68;
use strict;
use Parse::MediaWikiDump;

my $file = 't/pages_test.xml';
my $fh;
my $pages;

test_all($file);

open($fh, $file) or die "could not open $file: $!";

test_all($fh);

sub test_all {
	$pages = Parse::MediaWikiDump::Pages->new(shift);

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
	ok($page->title eq 'Title Test Value');
	ok($page->id == 1);
	ok($page->timestamp eq '2005-07-09T18:41:10Z');
	ok($page->username eq 'Username Test Value');
	ok($page->userid == 1292);
	ok($$text eq "Text Test Value\n");
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
