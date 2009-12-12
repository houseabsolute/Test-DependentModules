 use strict;
 use warnings;

 use Test::MyDeps qw( test_module );
 use Test::More tests => 2;

 test_module( 'Exception::Class' );
 test_module( 'CPAN::Test::Dummy::Perl5::Build::Fails' );
