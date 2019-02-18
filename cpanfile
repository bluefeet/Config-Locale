requires 'Config::Any' => 0.04;
requires 'Hash::Merge' => 0.12;
requires 'Algorithm::Loops' => 1.031;
requires 'Path::Tiny' => '0.091';
requires 'List::MoreUtils' => '0.428';

requires 'Carp';
requires 'Scalar::Util';

on test => sub {
    requires 'Test2::V0' => '0.000094';
};
