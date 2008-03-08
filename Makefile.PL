use 5.006001;

use ExtUtils::MakeMaker;

WriteMakefile(

	NAME         => 'Parallel::SubFork',
	VERSION_FROM => 'lib/Parallel/SubFork.pm',

	PREREQ_PM => {
		Carp                  => 0,
		POSIX                 => 0,
		Class::Accessor::Fast => 0,
	},
	

	ABSTRACT_FROM => 'lib/Parallel/SubFork.pm',
	AUTHOR        => 'Emmanuel Rodriguez <emmanuel.rodriguez@gmai..com>',
);
