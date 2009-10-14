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
    'Test::More' => 0,
    'XML::Parser' => 0,
    'List::Util' => 0,
    'Object::Destroyer' => 0,
    'Test::Exception' => 0,
    'Scalar::Util' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Parse-MediaWikiDump-*' },
);
