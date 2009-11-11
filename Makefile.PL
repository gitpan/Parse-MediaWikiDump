use strict;
use warnings;
use ExtUtils::MakeMaker;


WriteMakefile(
    NAME                => 'Parse::MediaWikiDump',
    AUTHOR              => 'Tyler Riddle <triddle@gmail.com>',
    VERSION_FROM        => 'lib/Parse/MediaWikiDump.pm',
    ABSTRACT_FROM       => 'lib/Parse/MediaWikiDump.pm',
    PL_FILES            => {},
    PREREQ_PM => {
    'PadWalker' => 0,
    'Devel::Cycle' => '1.11',
    'Test::Memory::Cycle' => 0,
    'Test::More' => 0,
    'Test::Exception' => 0,
    'XML::Parser' => 0,
    'List::Util' => 0,
    'Scalar::Util' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Parse-MediaWikiDump-*' },
);
