#!/usr/bin/perl

use strict;
use warnings;

use POSIX qw(_exit);

use Test::More tests => 4;

BEGIN {
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
	my $return = 42;
	
	++$return unless $$ != $PID;
	_exit($return);
	
	return ++$return;
}


sub task_exec {
	sleep 3;
	my $return = 12;

	++$return unless $$ != $PID;
	exec('perl', '-le', "exit($return);") or _exit(++$return);
}
