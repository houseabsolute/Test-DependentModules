use strict;
use warnings;

use Class::Load qw( load_class );

use Test::DependentModules qw( test_module );
use Test::More;

if ( eval { load_class('Pod::Readme') } ) {
    plan skip_all => 'This test requires that Pod::Readme _not_ be installed';
}

test_module('MooseX::Semantic');

done_testing();
