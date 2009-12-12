package Test::MyDeps;

use strict;
use warnings;

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

our @EXPORT_OK = qw( test_all_my_deps test_distro );

# By default, when CPAN is told to be silent, it sends output to a log
# file. We don't want that to happen.
BEGIN
{
    $CPAN::Be_Silent = 1;

    package CPAN::Shell;

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

    test_distro($_) for @deps;
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

sub test_distro {
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

# ABSTRACT: Test all modules which depend on your module
