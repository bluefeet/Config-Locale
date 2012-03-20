package Config::Locale;
use Moose;
use namespace::autoclean;

=head1 NAME

Config::Locale - Load and merge locale-specific configuration files.

=head1 SYNOPSIS

    use Config::Locale;
    
    my $locale = Config::Locale->new(
        identity => ['db', '1', 'qa'],
        directory => '/path/to/configs/',
    );
    
    my $config = $locale->config();

=head1 DESCRIPTION

This module takes an identity array, determines the permutations of the identity using
L<Algorithm::Loops>, loads configuration files using L<Config::Any>, and finally combines
the configurations using L<Hash::Merge>.

So, given this setup:

    Config::Locale->new(
        identity => ['db', '1', 'qa'],
        suffix   => '.yml',
    );

The following configuration files will be looked for (listed from least specific to most):

    default.yml
    all.all.qa.yml
    all.1.all.yml
    all.1.qa.yml
    db.all.all.yml
    db.all.qa.yml
    db.1.all.yml
    db.1.qa.yml

For each file found the contents will be parsed and then merged together to produce the
final configuration hash.  The hashes will be merged so that the most specific configuration
file will take precedence over the least specific files.  So, in the example above,
"db.1.qa.yml" values will overwrite values from "default.yml".

=cut

use Config::Any;
use MooseX::Types::Path::Class;
use Hash::Merge qw( merge );
use Algorithm::Loops qw( NestedLoops );

=head1 ARGUMENTS

=head2 identity

The identity that configuration files will be loaded for.  In a typical hostname-basedc
configuration setup this will be the be the parts of the hostname that declare the class,
number, and cluster that the current host identifies itself as.  But, this could be any
list of values.

=cut

has identity => (
    is       => 'ro',
    isa      => 'ArrayRef[Str]',
    required => 1,
);

=head2 directory

The directory to load configuration files from.  Defaults to the current
directory.

=cut

has directory => (
    is         => 'ro',
    isa        => 'Path::Class::Dir',
    coerce     => 1,
    lazy_build => 1,
);
sub _build_directory {
    return '.';
}

=head2 wildcard

The wildcard string to use when constructing the configuration filenames.
Defaults to "all".  This may be explicitly set to undef wich will cause
the wildcard string to not be added to the filenames at all.

=cut

has wildcard => (
    is         => 'ro',
    isa        => 'Maybe[Str]',
    lazy_build => 1,
);
sub _build_wildcard {
    return 'all';
}

=head2 default

The name of the configuration file that contains the default configuration.
Defaults to "default".  This may be explcitly set to undef which will cause
the default configuration file to look just like all the other configuration
files, just using the L</wildcard> for all of the identity values.

=cut

has default => (
    is         => 'ro',
    isa        => 'Maybe[Str]',
    lazy_build => 1,
);
sub _build_default {
    return 'default';
}

=head2 separator

The character that will be used to separate the identity keys in the
configuration filenames.  Defaults to ".".

=cut

has separator => (
    is => 'ro',
    isa => 'Str',
    lazy_build => 1,
);
sub _build_separator {
    return '.';
}

=head2 prefix

An optional prefix that will be prepended to the configuration filenames.

=cut

has prefix => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);
sub _build_prefix {
    return '';
}

=head2 suffix

An optional suffix that will be apended to the configuration filenames.
Typically this will need to be used to specify the filename extension for
the particular configuration format you are using, such as ".ini", ".yml",
etc.

=cut

has suffix => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);
sub _build_suffix {
    return '';
}

=head1 ATTRIBUTES

=head2 config

Contains the final configuration hash as merged from the hashes in L</configs>.

=cut

has config => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
    init_arg   => undef,
);
sub _build_config {
    my ($self) = @_;

    my $config = {};
    foreach my $this_config (@{ $self->configs() }) {
        $config = merge( $this_config, $config );
    }

    return $config;
}

=head2 configs

Contains an array of hashrefs, one hashref for each file in L</stems> that
exists.

=cut

has configs => (
    is         => 'ro',
    isa        => 'ArrayRef[HashRef]',
    lazy_build => 1,
    init_arg   => undef,
);
sub _build_configs {
    my ($self) = @_;

    my $configs = Config::Any->load_stems({
        stems           => $self->stems(),
        use_ext         => 1,
    });

    return [
        map { values %$_ }
        @$configs
    ];
}

=head2 stems

Contains an array of L<Path::Class::File> objects for each value in L</combinations>.

=cut

has stems => (
    is         => 'ro',
    isa        => 'ArrayRef[Path::Class::File]',
    lazy_build => 1,
    init_arg   => undef,
);
sub _build_stems {
    my ($self) = @_;

    my $directory = $self->directory();
    my $separator = $self->separator();
    my $wildcard  = $self->wildcard();
    my $default   = $self->default();
    my $prefix    = $self->prefix();
    my $suffix    = $self->suffix();

    my @combinations = @{ $self->combinations() };
    if ($default) {
        shift @combinations;
        unshift @combinations, [ $default ];
    }

    my @stems;
    foreach my $combination (@combinations) {
        my @parts = @$combination;
        if ($wildcard) {
            @parts = map { defined($_) ? $_ : $wildcard } @parts;
        }
        else {
            @parts = grep { defined($_) } @parts;
        }

        push @stems, $directory->file( $prefix . join($separator, @parts) . $suffix );
    }

    return \@stems;
}

=head2 combinations

Holds an array of arrays containing all possible premutations of the
identity.

=cut

has combinations => (
    is         => 'ro',
    isa        => 'ArrayRef[ArrayRef]',
    lazy_build => 1,
    init_arg   => undef,
);
sub _build_combinations {
    my ($self) = @_;

    my $options = [
        map { [undef, $_] }
        @{ $self->identity() }
    ];

    return [
        NestedLoops(
            $options,
            sub { [ @_ ] },
        )
    ];
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@gmail.com>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

