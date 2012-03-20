#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Path::Class qw( file );

BEGIN{ use_ok('Config::Locale') }

my $config = Config::Locale->new( identity => [qw( this that those )] );
is_deeply(
    $config->combinations(),
    [
        [undef, undef, undef],
        [undef, undef, 'those'],
        [undef, 'that', undef],
        [undef, 'that', 'those'],
        ['this', undef, undef],
        ['this', undef, 'those'],
        ['this', 'that', undef],
        ['this', 'that', 'those'],
    ],
    'correct combinations',
);

my $config_dir = file( $0 )->dir->subdir('config');

my @test_cases = (
    [ [qw( foo foo foo )] => { this=>'that', what=>'yes', bar=>'no' } ],
    [ [qw( foo foo bar )] => { this=>'that', what=>'yes', bar=>'yes' } ],
);

foreach my $case (@test_cases) {
    my ($identity, $expected) = @$case;

    my $config = Config::Locale->new(
        directory => $config_dir,
        identity  => $identity,
    )->config();

    is_deeply(
        $config,
        $expected,
        'config for ' . join('.', @$identity) . ' looks right',
    );
}

done_testing;
