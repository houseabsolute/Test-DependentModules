use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
    module_name => 'Test::DependentModules',
    license     => 'perl',
    requires    => {
        'autodie'          => '0',
        'CPAN'             => '1.9402',
        'CPANDB'           => '0.12',
        'Cwd'              => '0',
        'Exporter'         => '0',
        'File::chdir'      => '0',
        'File::Spec'       => '0',
        'File::Path'       => '0',
        'File::Temp'       => '0',
        'IO::Handle::Util' => '0',
        'IPC::Run3'        => '0',
        'Test::More'       => '0',
    },
    build_requires => {
        'Test::More' => '0',
    },
    create_readme      => 1,
    sign               => 1,
    create_makefile_pl => 'traditional',
    meta_merge         => {
        resources => {
            bugtracker =>
                'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Test-DependentModules',
            repository => 'http://hg.urth.org/hg/Test-DependentModules',
        },
    },
);

$build->create_build_script;
