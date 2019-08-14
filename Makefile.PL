use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'All::Cores',
    VERSION_FROM      => 'lib/All/Cores.pm', # finds $VERSION
    PREREQ_PM         => { Sys::Info => 0.7811,
			   Sys::Info::Device::CPU => 0.7807,
			   JSON::XS => 4.02 }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/All/Cores.pm', # retrieve abstract from module
       AUTHOR         => 'Chris Drake<cdrake@cpan.org>') : ()),
);
