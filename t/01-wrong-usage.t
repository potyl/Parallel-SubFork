#!/usr/bin/perl

use strict;
use warnings;

use POSIX qw(WNOHANG);

use Test::More tests => 6;

BEGIN {
	use_ok('Parallel::SubFork');
}

my $PID = $$;
my $MANAGER;
my $TASK;

exit main();


sub main {
	
	# Create a new task
	$MANAGER = Parallel::SubFork->new();
	isa_ok($MANAGER, 'Parallel::SubFork');
	
	# Start a sub task and try to do a wait_for there
	my $task_wait_for_all = $MANAGER->start(\&task_wait_for_all);
	my $task_start = $MANAGER->start(\&task_start);
	$TASK = $MANAGER->start(sub {return 42;});
	my $task_wait_for = $MANAGER->start(\&task_wait_for);

	# Wait for the task to resume
	$MANAGER->wait_for_all();
	
	is($task_wait_for_all->exit_code, 75, "Child process can't call wait_for_all()");
	is($task_start->exit_code, 61, "Child process can't call start()");
	is($TASK->exit_code, 42, "Generic task");
	is($task_wait_for->exit_code, 23, "Child process can't call start()");
	
	return 0;
}


#
# Test that a task can't call $manager->wait_for_all()
#
sub task_wait_for_all {
	my (@args) = @_;

	my $return = 75;

	++$return unless $$ != $PID;

	eval {
		$MANAGER->wait_for_all();
		++$return;
	};
	if (my $error = $@) {
		my $match = "Process $$ is not the main dispatcher";
		++$return unless $error =~ /^\Q$match\E/;
	}

	return $return;
}


#
# Test that a task can't call $manager->start()
#
sub task_start {
	my (@args) = @_;

	my $return = 61;

	++$return unless $$ != $PID;

	eval {
		$MANAGER->start(
			sub {
				die "***** TEST FAILED ($$ <-> $PID) *****";
			}
		);
		++$return;
	};
	if (my $error = $@) {
		my $match = "Process $$ is not the main dispatcher";
		++$return unless $error =~ /^\Q$match\E/;
	}

	return $return;
}


#
# Test that a task can't call $task->wait_for()
#
sub task_wait_for {
	my (@args) = @_;

	my $return = 23;

	++$return unless $$ != $PID;

	eval {
		$TASK->wait_for();
		++$return;
	};
	if (my $error = $@) {
		my $match = "Only the parent process can wait for the task";
		++$return unless $error =~ /^\Q$match\E/;
	}

	return $return;
}
