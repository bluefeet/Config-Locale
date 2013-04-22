#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

BEGIN{ use_ok('Config::Locale') }

my $config = Config::Locale->new( identity => [qw( c a b )], algorithm => 'PERMUTE' );

# The order of these values can be depended on as the algorithm used to find the
# permutations works in a known order and the initial combinations passed to it
# are done so in a sorted order.
is_deeply(
    $config->combinations(),
    [
        [],
        [qw( b )],
        [qw( a )],
        [qw( c )],
        [qw( a b )],
        [qw( b a )],
        [qw( b c )],
        [qw( c b )],
        [qw( a c )],
        [qw( c a )],
        [qw( a b c )],
        [qw( a c b )],
        [qw( b a c )],
        [qw( b c a )],
        [qw( c a b )],
        [qw( c b a )],
    ],
    'permute has correct combinations',
);

done_testing;
