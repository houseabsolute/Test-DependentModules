use strict;
use warnings;

use Test::MyDeps qw( test_distro );
use Test::More tests => 2;

test_distro( 'Exception::Class' );
test_distro( 'CPAN::Test::Dummy::Perl5::Build::Fails' );
