#!perl -w

use Test::Simple tests => 11;
use strict;
use Parse::MediaWikiDump;

my $pages = Parse::MediaWikiDump::Pages->new('test_data.xml');
my $page = $pages->page;
my $text = $page->text;

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
