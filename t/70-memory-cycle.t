use strict;
use warnings;

use Test::Memory::Cycle tests => 11;
use Parse::MediaWikiDump;

my $pages = Parse::MediaWikiDump->pages('t/pages_test.xml');
my $revisions = Parse::MediaWikiDump->revisions('t/revisions_test.xml');

memory_cycle_ok($pages);
while(defined(my $page = $pages->next)) {
	memory_cycle_ok($page);
}

memory_cycle_ok($revisions);
while(defined(my $revision = $revisions->next)) {
	memory_cycle_ok($revision);
}