#!/usr/bin/perl

use strict;
use warnings;

use POSIX qw(WNOHANG pause);

use Test::More tests => 26;

BEGIN {
	use_ok('Parallel::SubFork::Task');
}

my $PID = $$;

exit main();


sub main {
	
	test_task_creation();	
	
	# Start a tastk through new(), execute()
	{
		my $task = Parallel::SubFork::Task->new(\&task, 1 .. 10);
		$task->execute();
		test_task_run($task);
	}

	# Start a tastk through start()
	{
		my $task = Parallel::SubFork::Task->start(\&task, 1 .. 10);
		test_task_run($task);
	}
	
	return 0;
}



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


sub test_task_run {
	my ($task) = @_;

	isa_ok($task, 'Parallel::SubFork::Task');
	
	# Make sure that the task is in a different process
	ok($$ != $task->pid, "Taks has a different PID");
	{
		my $kid = waitpid($task->pid, WNOHANG);
		is($kid, 0, "Child process still running");
	}
	# The task is expected to be in pause, so let's wake it up
	kill HUP => $task->pid;
	
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


sub task {
	my (@args) = @_;
	my $return = 57;
	
	local $SIG{HUP} = sub {return;};
	
	# This paused is needed because we will actually test that the process is
	# running
	pause();

	++$return unless $$ != $PID;
	
	my @wanted = qw(1 2 3 4 5 6 7 8 9 10);
	++$return unless eq_array(\@args, \@wanted);
	
	return $return;
}
