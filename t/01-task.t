#!/usr/bin/perl

use strict;
use warnings;

use POSIX qw(WNOHANG);

use Test::More tests => 17;

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
	
	# Make sure that we are the main dispatcher
	$manager->_assert_is_dispatcher();
	pass("Parent is the dispatcher");
	
	# Assert that there are no tasks
	{
		my @tasks = $manager->tasks();
		is_deeply(\@tasks, [], "No tasks in list context");
	
		my $tasks = $manager->tasks();
		is($tasks, 0, "No tasks in scalar context");
		
		foreach my $task ($manager->tasks()) {
			fail("Expected no task but got $task");
		}
	}
	
	
	# Start a sub task
	my $task = $manager->start(\&task, 1 .. 10);
	isa_ok($task, 'Parallel::SubFork::Task');
	
	# Assert that there's a task
	{
		my @tasks = $manager->tasks();
		is_deeply(\@tasks, [$task], "One task in list context");
	
		my $tasks = $manager->tasks();
		is($tasks, 1, "One task in scalar context");
		
		foreach my $tmp ($manager->tasks()) {
			is($tmp, $task, "Looping through tasks")
		}
	}

	
	# Make sure that the task is in a different process
	ok($$ != $task->pid, "Taks has a different PID");
	{
		my $kid = waitpid($task->pid, WNOHANG);
		is($kid, 0, "Child process still running");
	}
	
	# Wait for the task to resume
	$task->wait_for();
	is($task->exit_code, 57, "Task exit code is fine");
	is($task->status, 57 << 8, "Task status is fine");

	is_deeply(
		[ $task->args ], 
		[ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ], 
		"Task args are intact"
	);

	# Wait some more, is useless but it should work
	$task->wait_for();
	is($task->exit_code, 57, "Second wait on the same task, exit code fine");
	is($task->status, 57 << 8, "Second wait on the same task, status fine");
	

	# Make sure that there are no other tasks
	{
		my $kid = waitpid(-1, WNOHANG);
		is($kid, -1, "No more processes");
	}
	
	return 0;
}


sub task {
	my (@args) = @_;
	sleep 2;
	my $return = 57;

	++$return unless $$ != $PID;
	
	my @wanted = qw(1 2 3 4 5 6 7 8 9 10);
	
	++$return unless eq_array(\@args, \@wanted);
#	is_deeply(\@args, \@wanted, "Task argument passed successfully");
	
	return $return;
}
