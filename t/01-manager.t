#!/usr/bin/perl

use strict;
use warnings;

use POSIX qw(WNOHANG);


use Test::More;

# Make sure that the test don't get executed under Windows
BEGIN {

	if ($^O eq 'MSWin32') {
		plan skip_all => "Fork is broken under windows and IPC::SysV doesn't exit.";
	}
	else {
		plan tests => 21;
		use_ok('Parallel::SubFork');
	}

}

# Load the custom utilities for semaphores
use FindBin;
use lib $FindBin::Bin;
use Tsemaphore;


my $PID = $$;


exit main();


sub main {
	
	# Create a semaphore holding 2 values
	semaphore_init();
	
	
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
	
	# Make sure that there's no hanging, it's better to fail the test due to a
	# timeout than to leave the test haging there forever.
	alarm(10);
	
	
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


	# Wait for the kid to be ready
	my $return = semaphore_wait_for($SEMAPHORE_POINT_A);
	ok($return, "Added resource to semaphore A");

	
	# Make sure that the task is in a different process
	ok($$ != $task->pid, "Taks has a different PID");
	{
		my $kid = waitpid($task->pid, WNOHANG);
		is($kid, 0, "Child process still running");
	}

	
	# Tell the kid that we finish checking it, it can now resume
	$return = semaphore_let_go($SEMAPHORE_POINT_B);
	ok($return, "Removed resource to semaphore B");



	
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


#
# Tests pases if 57 is returned
#
sub task {
	my (@args) = @_;
	
	# Make sure that there's no hanging
	alarm(10);
	

	# Tell the parent that we are ready
	semaphore_let_go($SEMAPHORE_POINT_A) or return 10;

	
	# Wait for the parent to let us go further
	semaphore_wait_for($SEMAPHORE_POINT_B) or return 11;

	return 12 unless $$ != $PID;
	
	my @wanted = qw(1 2 3 4 5 6 7 8 9 10);
	return 13 unless eq_array(\@args, \@wanted);
	
	return 57;
}
