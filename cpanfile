

requires 'Config::Any' => 0.04;
requires 'Hash::Merge' => 0.12;
requires 'Algorithm::Loops' => 1.031;
requires 'Path::Class' => 0;
requires 'Carp' => 0;
requires 'Scalar::Util' => 0;
requires 'List::MoreUtils' => 0;

on test => sub {
   requires 'Test::Simple' => 0.94;
};

