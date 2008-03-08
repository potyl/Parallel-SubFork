#!/usr/bin/perl

use strict;
use warnings;

use POSIX qw(WNOHANG);

use Test::More tests => 13;

BEGIN {
	use_ok('Parallel::SubFork');
}

exit main();


sub main {
	
	my $PID = $$;
	
	# Create a new task
	my $manager = Parallel::SubFork->new();
	isa_ok($manager, 'Parallel::SubFork');
	
	# Make sure that we are the main dispatcher
	$manager->_assert_is_dispatcher();
	pass("Parent is the dispatcher");
	
	# Assert that there are no tasks
	{
		my @tasks = $manager->tasks();
		is_deeply(\@tasks, [], "No tasks in list context");
	
		my $tasks = $manager->tasks();
		is($tasks, 0, "No tasks in scalar context");
	}
	
	
	# Start a sub task
	my $task = $manager->start(
		sub {
			sleep 2;
			ok($$ != $PID, "Task is running in a child process $$ != $PID");
			return 0;
		}
	);
	isa_ok($task, 'Parallel::SubFork::Task');
	
	# Assert that there's a task
	{
		my @tasks = $manager->tasks();
		is_deeply(\@tasks, [$task], "One task in list context");
	
		my $tasks = $manager->tasks();
		is($tasks, 1, "One task in scalar context");
	}

	
	# Make sure that the task is in a different process
	ok($$ != $task->pid, "Taks has a different PID");
	{
		my $kid = waitpid($task->pid, WNOHANG);
		is($kid, 0, "Child process still running");
	}
	
	# Wait for the task to resume
	$task->wait_for();
	is($task->exit_code, 0, "Task returned successfully");


	# Wait some more, is useless but it should work
	$task->wait_for();
	is($task->exit_code, 0, "Second wait on the same task");
	

	# Make sure that there are no other tasks
	{
		my $kid = waitpid(-1, WNOHANG);
		is($kid, -1, "No more processes");
	}
	
	printf "Task status: %s\n", $task->status;
	printf "Task exit: %s\n", $task->exit_code;
	printf "Task args: %s\n", join (", ", $task->args);
	
	return 0;
}
