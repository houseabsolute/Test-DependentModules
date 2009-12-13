use strict;
use warnings;

use Test::DependentModules qw( test_module );
use Test::More;

plan skip_all => 'Make $ENV{TDM_HACK_TESTS} true to run this test'
    unless $ENV{TDM_HACK_TESTS};

plan tests => 2;

test_module('Exception::Class');
test_module('CPAN::Test::Dummy::Perl5::Build::Fails');
