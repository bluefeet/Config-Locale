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
    override

For each file found the contents will be parsed and then merged together to produce the
final configuration hash.  The hashes will be merged so that the most specific configuration
file will take precedence over the least specific files.  So, in the example above,
"db.1.qa" values will overwrite values from "db.1.all".

=cut

use Moose::Util::TypeConstraints;
use Config::Any;
use MooseX::Types::Path::Class;
use Hash::Merge;
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
    isa        => 'Str|Undef',
    lazy_build => 1,
);
sub _build_wildcard {
    return 'all';
}

=head2 default_stem

A stem used to load default configuration values before any other
configuration files are loaded.

Defaults to "default".  A relative path may be specified which will be assumed
to be relative to L</directory>.  If an absolute path is used then no change
will be made.  Either a scalar or a L<Path::Class::File> object may be used.

Note that L</prefix> and L</suffix> are not applied to this stem.

=cut

has default_stem => (
    is         => 'ro',
    isa        => 'Path::Class::File|Undef',
    coerce     => 1,
    lazy_build => 1,
);
sub _build_default_stem {
    return 'default';
}

=head2 override_stem

This works just like L</default_stem> except that the configuration values
from this stem will override those from all other configuration files.

Defaults to "override".

=cut

has override_stem => (
    is         => 'ro',
    isa        => 'Path::Class::File|Undef',
    coerce     => 1,
    lazy_build => 1,
);
sub _build_override_stem {
    return 'override';
}

=head2 separator

The character that will be used to separate the identity keys in the
configuration filenames.  Defaults to ".".

=cut

subtype 'Config::Locale::Types::Separator',
    as 'Str',
    where { length($_) == 1 },
    message { 'The separator must be a single character' };

has separator => (
    is => 'ro',
    isa => 'Config::Locale::Types::Separator',
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

C<PERMUTE> finds configuration files that includes any number of the identity
values in any order.  Due to the high CPU demands of permutation algorithms this does
not actually generate every possible permutation - instead it finds all files that
match the directory/prefix/separator/suffix and filters those for values in the
identity and is very fast.

=cut

enum 'Config::Locale::Types::Algorithm', ['NESTED', 'PERMUTE'];

has algorithm => (
    is         => 'ro',
    isa        => 'Config::Locale::Types::Algorithm',
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
    my $prefix    = $self->prefix();
    my $suffix    = $self->suffix();

    my @combinations = @{ $self->combinations() };

    my @stems;
    foreach my $combination (@combinations) {
        my @parts = @$combination;
        push @stems, $directory->file( $prefix . join($separator, @parts) . $suffix );
    }

    return [
        $self->default_stem->absolute( $directory ),
        @stems,
        $self->override_stem->absolute( $directory ),
    ];
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

    if ($self->algorithm() eq 'NESTED') {
        return $self->_nested_combinations();
    }
    elsif ($self->algorithm() eq 'PERMUTE') {
        return $self->_permute_combinations();
    }

    die 'Unknown algorithm'; # Shouldn't ever get to this.
}

sub _nested_combinations {
    my ($self) = @_;

    my $wildcard = $self->wildcard();

    my $options = [
        map { [$wildcard, $_] }
        @{ $self->identity() }
    ];

    return [
        # If the wildcard is undef then we will have one empty array that needs removal.
        grep { @$_ > 0 }

        # If the wildcard is undef then we need to strip out the undefs.
        map { [ grep { defined($_) } @$_ ] }

        # Run arbitrarily deep foreach loop.
        NestedLoops(
            $options,
            sub { [ @_ ] },
        )
    ];
}

sub _permute_combinations {
    my ($self) = @_;

    my $wildcard  = $self->wildcard();
    my $prefix    = $self->prefix();
    my $suffix    = $self->suffix();
    my $separator = $self->separator();

    my $id_lookup = {
        map { $_ => 1 }
        @{ $self->identity() },
    };

    $id_lookup->{$wildcard} = 1 if defined $wildcard;

    my @combos;
    foreach my $file ($self->directory->children()) {
        next if $file->is_dir();

        if ($file->basename() =~ m{^$prefix(.*)$suffix\.}) {
            my @parts = split(/[$separator]/, $1);
            my $matches = 1;
            foreach my $part (@parts) {
                next if $id_lookup->{$part};
                $matches = 0;
                last;
            }
            if ($matches) { push @combos, \@parts }
        }
    }

    return [
        sort { @$a <=> @$b }
        @combos
    ];

    return \@combos;
}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeet@gmail.com>

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

