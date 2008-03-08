#!/usr/bin/perl

use strict;
use warnings;

use POSIX qw(_exit);

use Test::More tests => 4;

BEGIN {

	# Make sure that we don't count the tests because the count will go wrong
	# when forking processes
	Test::More->builder->use_numbers(0);

	use_ok('Parallel::SubFork');
}

my $PID = $$;

exit main();


sub main {
	
	# Create a new task
	my $manager = Parallel::SubFork->new();
	isa_ok($manager, 'Parallel::SubFork');
	
	my $task1 = $manager->start(\&task_exit);
	my $task2 = $manager->start(\&task_exec);
	
	$manager->wait_for_all();
	
	is($task1->exit_code, 42, "Exit worked properly");
	is($task2->exit_code, 12, "Exec worked properly");
	
	return 0;
}


sub task_exit {
	sleep 2;
	ok($$ != $PID, "Task is running in a child process $$ != $PID");
	pass("Child process forked. Going to exit");
	_exit(42);
	fail("Failed to exit");
}


sub task_exec {
	sleep 3;
	ok($$ == $PID, "Task is running in a child process $$ != $PID");
	pass("Child process forked. Executing exec");
	exec('perl', '-le', 'exit(12);');
}
