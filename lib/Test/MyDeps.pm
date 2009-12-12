package Test::MyDeps;

use strict;
use warnings;

our $VERSION = '0.01';

# CPAN::Reporter spits out random output we don't want, and we don't want to
# report these tests anyway.
BEGIN { $INC{'CPAN/Reporter.pm'} = 0 }

use autodie;
use CPAN;
use CPAN::Shell;
use CPANDB;
use Cwd qw( abs_path );
use Exporter qw( import );
use File::chdir;
use File::Spec;
use File::Temp qw( tempdir );
use IPC::Run3 qw( run3 );
use Test::More;

our @EXPORT_OK = qw( test_all_my_deps test_module );

# By default, when CPAN is told to be silent, it sends output to a log
# file. We don't want that to happen.
BEGIN
{
    $CPAN::Be_Silent = 1;

    package
        CPAN::Shell;

    use IO::Handle::Util qw( io_from_write_cb );

    no warnings 'redefine';

    my $fh;
    if ( $ENV{TEST_PERL_MD_CPAN_VERBOSE} ) {
        $fh = io_from_write_cb( sub { Test::More::diag( $_[0] ) } );
    }
    else {
        open $fh, '>', File::Spec->devnull();
    }

    sub report_fh {$fh}
}

CPAN::HandleConfig->load();
CPAN::Shell::setup_output();
CPAN::Index->reload();

$CPAN::Config->{test_report} = 0;
$CPAN::Config->{mbuildpl_arg} .= ' --quiet';
$CPAN::Config->{prerequisites_policy} = 'follow';
$CPAN::Config->{make_install_make_command}    =~ s/^sudo //;
$CPAN::Config->{mbuild_install_build_command} =~ s/^sudo //;
$CPAN::Config->{make_install_arg} =~ s/UNINST=1//;
$CPAN::Config->{mbuild_install_arg} =~s /--uninst\s+1//;

$ENV{PERL5LIB} = join q{:}, ( $ENV{PERL5LIB} || q{} ),
    File::Spec->catdir( _temp_lib_dir(), 'lib', 'perl5' );
$ENV{PERL_AUTOINSTALL}    = '--defaultdeps';
$ENV{PERL_MM_USE_DEFAULT} = 1;

sub test_all_my_deps {
    my $module = shift;
    my $params = shift;

    my @deps = _get_deps( $module, $params );

    plan tests => scalar @deps;

    test_module($_) for @deps;
}

sub _get_deps {
    my $module = shift;
    my $params = shift;

    $module =~ s/::/-/g;

    my $distro = CPANDB->distribution($module);

    my @deps = CPANDB::Dependency->select(
        'where dependency = ? and ( core is null or core >= ? )',
        $module, $]
    );

    my $allow
        = $params->{exclude}
        ? sub { $_[0] !~ /$params->{exclude}/ }
        : sub {1};

    return map { $_->distribution() }
        grep   { $_ !~ /^(?:Task|Bundle)/ }
        grep   { $allow->($_) } @deps;
}

sub test_module {
    my $name = shift;

    my $log = _get_log();

    $name =~ s/-/::/g;

    my $dist = _get_distro($name);

    unless ($dist) {
        print {$log} "UNKNOWN : $name (not on CPAN?)\n";

    SKIP:
        {
            skip "Could not find $name on CPAN", 1;
        }

        return;
    }

    _install_prereqs($dist);

    my ( $passed, $output, $stderr ) = _run_tests_for_dir( $dist->dir() );

    my $status = $passed && $stderr ? 'WARN' : $passed ? 'PASS' : 'FAIL';

    my $summary = "$status: $name - " . $dist->base_id();

    print {$log} "$summary\n";

    ok( $passed, "$name passed all tests" );

    return if $passed && !$stderr;

    print {$log} "\n\n";
    print {$log} q{-} x 50;
    print {$log} "\n";
    print {$log} "$name\n\n";
    print {$log} "$output\n\n";
}

{
    my $Log;

    sub _get_log {
        return $Log if defined $Log;

        my $log_file = $ENV{PERL_TEST_MD_LOG} || File::Spec->devnull();

        open $Log, '>', $log_file;

        return $Log;
    }
}

sub _get_distro {
    my $name = shift;

    my @mods = CPAN::Shell->expand( 'Module', $name );

    die "Cannot resolve $name to a single CPAN module"
        if @mods > 1;

    return unless @mods;

    my $dist = $mods[0]->distribution();

    $dist->get();

    return $dist;
}

sub _install_prereqs {
    my $dist = shift;

    $dist->make();

    my $install_dir = _temp_lib_dir();

    local $CPAN::Config->{makepl_arg} .= " INSTALL_BASE=$install_dir";
    local $CPAN::Config->{mbuild_install_arg}
        .= " --install_base $install_dir";

    for my $prereq (
        $dist->unsat_prereq('configure_requires_later'),
        $dist->unsat_prereq('later')
        ) {
        if ( $prereq->[0] eq 'perl' ) {

        }
        else {
            my $dist = _get_distro( $prereq->[0] );
            _install_prereqs($dist);
            $dist->notest();
            $dist->install();
        }
    }
}

{
    my $Dir = tempdir( CLEANUP => 1 );

    sub _temp_lib_dir {
        return $Dir;
    }
}

sub _run_tests_for_dir {
    my $dir = shift;

    local $CWD = $dir;

    if ( -f "Build.PL" ) {
        return
            unless _run_commands(
            ['./Build'],
            );
    }
    else {
        return
            unless _run_commands(
            ['make'],
            );
    }

    return _run_tests();
}

sub _run_commands {
    for my $cmd (@_) {
        my $output;

        unless ( run3 $cmd, \undef, \$output, \$output ) {
            return ( 0, $output );
        }
    }

    return 1;
}

sub _run_tests {
    my $output = q{};
    my $error  = q{};

    my $stderr = sub {
        my $line = shift;

        $output .= $line;
        $error  .= $line;
    };

    if ( -f 'Build.PL' ) {
        run3 [qw( ./Build test )], undef, \$output, $stderr;
    }
    else {
        run3 [qw( make test )], undef, \$output, $stderr;
    }

    my $passed = $output =~ /Result: PASS/;

    return ( $passed, $output, $error );
}

1;

__END__

=pod

=head1 NAME

Test::MyDeps - Test all modules which depend on your module

=head1 SYNOPSIS

  use Test::MyDeps qw( test_all_my_deps );

  test_all_my_deps('My::Module');

  # or ...

  use Test::MyDeps qw( test_module );
  use Test::More tests => 3;

  test_module('Exception::Class');
  test_module('DateTime');
  test_module('Log::Dispatch');

=head1 DESCRIPTION

B<WARNING>: The tests this module does should B<never> be included as part of
a normal CPAN install!

This module is intended as a tool for module authors who would like to easily
test that a module release will not break dependencies. This is particularly
useful for module authors (like myself) who have modules which are a
dependency of many other modules.

=head2 How It Works

Internally, this module will download dependencies from CPAN and run their
tests. If those dependencies in turn have unsatisfied dependencies, they are
installed into a temporary directory. These second-level (and third-, etc)
dependencies are I<not> tested.

In order to avoid prompting, this module attempts set
C<$ENV{PERL_AUTOINSTALL}> to C<--defaultdeps> and sets
C<$ENV{PERL_MM_USE_DEFAULT}> to a true value.

Nonetheless, some ill-behaved modules will I<still> wait for a
prompt. Unfortunately, because of the way this module attempts to keep output
to a minimum, you won't see these prompts. Patches are welcome.

=head1 FUNCTIONS

This module optionally exports two functions:

=head2 test_all_my_deps( $module, { exclude => qr/.../ } )

Given a module name, this function uses C<CPANDB> to find all its dependencies
and test them. It will call the C<plan()> function from L<Test::More> for you.

If you want to exclude some dependencies, you can pass a regex which will be
used to exclude any matching distributions.

Additionally, any distribution name starting with "Task" or "Bundle" is always
excluded.

=head2 test_module($name)

Given a module name, this function will test it. You can use this if you'd
prefer to hard code a list of modules to test.

In this case, you will have to handle your own test planning.

=head1 PERL5LIB FOR DEPENDENCIES

If you want to include a module-to-be-released in the path seen by
dependencies, you must make sure that the correct path ends up in
C<$ENV{PERL5LIB}>. If you use C<prove -l> or C<prove -b> to run tests, then
that will happen automatically.

=head1 WARNINGS, LOGGING AND VERBOSITY

By default, this module attempts to quiet down CPAN and the module building
toolchain as much as possible. However, when there are test failures in a
dependency it's nice to see the output.

In addition, if the tests spit out warnings but still pass, this will just be
treated as a pass.

This module can log all successes, warnings, failures, along with the full
output of the test suite for each dependency. To enable this, simply set
$ENV{PERL_TEST_MD_LOG} to the path of the log file.

You also can enable CPAN's output by setting the
C<$ENV{TEST_PERL_MD_CPAN_VERBOSE}> variable to a true value.

=head1 BUGS

Please report any bugs or feature requests to C<bug-test-mydeps@rt.cpan.org>,
or through the web interface at L<http://rt.cpan.org>.  I will be notified,
and then you'll automatically be notified of progress on your bug as I make
changes.

=head1 DONATIONS

If you'd like to thank me for the work I've done on this module, please
consider making a "donation" to me via PayPal. I spend a lot of free time
creating free software, and would appreciate any support you'd care to offer.

Please note that B<I am not suggesting that you must do this> in order for me
to continue working on this particular software. I will continue to do so,
inasmuch as I have in the past, for as long as it interests me.

Similarly, a donation made in this way will probably not make me work on this
software much more, unless I get so many donations that I can consider working
on free software full time, which seems unlikely at best.

To donate, log into PayPal and send money to autarch@urth.org or use the
button on this page: L<http://www.urth.org/~autarch/fs-donation.html>

=head1 AUTHOR

Dave Rolsky, E<lt>autarch@urth.orgE<gt>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Dave Rolsky, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
