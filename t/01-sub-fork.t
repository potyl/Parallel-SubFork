#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

# Make sure that the test don't get executed under Windows
BEGIN {

	if ($^O eq 'MSWin32') {
		plan skip_all => "Fork is broken under windows and IPC::SysV doesn't exit.";
	}
	else {
		plan tests => 12;
		use Parallel::SubFork qw(sub_fork);
	}

}

# Load the custom utilities for semaphores
use FindBin;
use lib $FindBin::Bin;
use Tsemaphore;


exit main();


sub main {

	# Make sure that there's no hanging, it's better to fail the test due to a
	# timeout than to leave the test haging there forever.
	alarm(10);
	
	# Create a semaphore holding 2 values
	semaphore_init();
	
	# Start a tastk through sub_forl()
	my $task = sub_fork(\&semaphore_task, 1 .. 10);
	test_semaphore_task_run($task);
	
	return 0;
}
