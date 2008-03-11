#!/usr/bin/perl

use strict;
use warnings;

use POSIX qw(WNOHANG);

# Load the custom utilities for semaphores
use FindBin;
use lib $FindBin::Bin;
use Tsemaphore;

use Test::More;

# Make sure that the test don't get executed under Windows
BEGIN {

	if ($^O eq 'MSWin32' and !$ENV{USE_IPC}) {
		plan skip_all => "Fork is broken under windows and IPC::SysV doesn't exit.";
	}
	else {
		plan tests => 33;
		use_ok('Parallel::SubFork::Task');
	}

}


my $PID = $$;


exit main();


sub main {

	# Make sure that there's no hanging, it's better to fail the test due to a
	# timeout than to leave the test haging there forever.
	alarm(10);
	
	# Test the default values of a task after it's creation, the task is not
	# started.
	test_task_creation();	


	# Create a semaphore holding 2 values
	semaphore_init();
	
	# Start a tastk through new(), execute()
	{
		semaphore_reset();
		my $task = Parallel::SubFork::Task->new(\&task, 1 .. 10);
		$task->execute();
		test_task_run($task);
	}

	# Start a tastk through start()
	{
		semaphore_reset();
		my $task = Parallel::SubFork::Task->start(\&task, 1 .. 10);
		test_task_run($task);
	}
	
	return 0;
}


#
# This test doesn't start a task, it simply creates one and checks for the
# default values.
#
sub test_task_creation {
	# Create a new task
	my $task = Parallel::SubFork::Task->new(\&task, 1 .. 10);
	isa_ok($task, 'Parallel::SubFork::Task');
	
	# Assert that the task is constructed properly
	{
		my @args = $task->args();
		is_deeply(
			\@args, 
			[1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 
			"Args are the same in list context"
		);
		
		my $args = $task->args();
		is($args, 10, "Args count is the same in scalar context");
		
	}
	is($task->code, \&task, "Code is the same");
	
	is($task->pid, undef, "New task PID is undef");
	is($task->exit_code, undef, "New task exit_code is undef");
	is($task->status, undef, "New task status is undef");
}


#
# Execute a task and test that it's running properly
#
sub test_task_run {
	my ($task) = @_;

	isa_ok($task, 'Parallel::SubFork::Task');
	
	# Wait for the kid to be ready
	my $return = semaphore_wait_for($SEMAPHORE_POINT_A);


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
