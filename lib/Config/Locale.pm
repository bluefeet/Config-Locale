package Config::Locale;
use Moose;
use namespace::autoclean;

=head1 NAME

Config::Locale - Load and merge locale-specific configuration files.

=head1 SYNOPSIS

    use Config::Locale;
    
    my $locale = Config::Locale->new(
        identity => \@values,
        directory => $config_dir,
    );
    
    my $config = $locale->config();

=head1 DESCRIPTION

This module takes an identity array, determines the permutations of the identity using
L<Algorithm::Loops>, loads configuration files using L<Config::Any>, and finally combines
the configurations using L<Hash::Merge>.

So, given this setup:

    Config::Locale->new(
        identity => ['db', '1', 'qa'],
    );

The following configuration files will be looked for (listed from least specific to most):

    default
    all.all.qa
    all.1.all
    all.1.qa
    db.all.all
    db.all.qa
    db.1.all
    db.1.qa

For each file found the contents will be parsed and then merged together to produce the
final configuration hash.  The hashes will be merged so that the most specific configuration
file will take precedence over the least specific files.  So, in the example above,
"db.1.qa" values will overwrite values from "default".

=cut

use Moose::Util::TypeConstraints;
use Config::Any;
use MooseX::Types::Path::Class;
use Hash::Merge;
use Algorithm::Loops qw( NestedLoops NextPermute );

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

Note that this argument is completely ignored if you are using the C<PERMUTE>
algorithm.

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
While it may seem like the right place, you probably should not be using
this to specify the extension of your configuration files.  L<Config::Any>
automatically tries many various forms of extensions without the need
to explicitly declare the extension that you are using.

=cut

has suffix => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);
sub _build_suffix {
    return '';
}

=head2 algorithm

Which algorithm used to determine, based on the identity, what configuration
files to consider for inclusion.

The default, C<NESTED>, keeps the order of the identity.  This is most useful
for identities that are derived from the name of a resource as resource names
(such as hostnames of machines) typically have a defined structure.

The C<PERMUTE> algorithm will shift the identity values around in all possible
permutations.  This is most useful when the identity contains attributes of a
resource.

=cut

enum 'Config::Locale::Algorithm', ['NESTED', 'PERMUTE'];

has algorithm => (
    is         => 'ro',
    isa        => 'Config::Locale::Algorithm',
    lazy_build => 1,
);
sub _build_algorithm {
    return 'NESTED';
}

=head2 merge_behavior

Specify a L<Hash::Merge> merge behavior.  The default is C<LEFT_PRECEDENT>.

=cut

has merge_behavior => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);
sub _build_merge_behavior {
    return 'LEFT_PRECEDENT';
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

    my $merge = Hash::Merge->new( $self->merge_behavior() );

    my $config = {};
    foreach my $this_config (@{ $self->configs() }) {
        $config = $merge->merge( $this_config, $config );
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

Holds an array of arrays containing all possible permutations of the
identity, per the specified L</algorithm>.

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

    my $combos = [
        NestedLoops(
            $options,
            sub { [ @_ ] },
        )
    ];

    if ($self->algorithm() eq 'PERMUTE') {
        $combos = [
            # Smaller arrays should be sorted before larger ones.
            sort { @$a <=> @$b }
            map {[
                sort # Must sort before calling NextPermute.
                grep { defined $_ } # The undefs would cause diplicate permutations.
                @$_
            ]}
            @$combos
        ];

        my @pcombos;
        foreach my $combo (sort { @$a <=> @$b } @$combos) {
            do { push @pcombos, [ @$combo ] }
            while (NextPermute( @$combo ));
        }

        $combos = \@pcombos;
    }

    return $combos;
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@gmail.com>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

