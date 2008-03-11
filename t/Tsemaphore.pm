#!/usr/bin/perl
package Tsemaphore;


use strict;
use warnings;

use IPC::SysV qw(IPC_PRIVATE S_IRWXU IPC_CREAT);
use IPC::Semaphore;

use Test::More;

# This is a testing framework so we can do ugly things like exporting symbols by
# default into the caller's context
use base 'Exporter';
our @EXPORT = qw(
	semaphore_init
	semaphore_reset
	semaphore_let_go
	semaphore_wait_for
	$SEMAPHORE_POINT_A
	$SEMAPHORE_POINT_B
);


# Semaphores are used for synchronizing the parent (main code) and the child
# (task). The idea is that the parent will check that the child is actually
# running. In order for this test to be successful the child has to be running!
# To ensure that the child is running semaphores are used. The child will not be
# allowed to finish until the parent has approved it. On the other hand the 
# parent will not be allowed to check for child's process until the child is
# alive and notifies the parent of his existence.
#
# Parent                 |  Child
# -----------------------|-----------
#                        |
# Init                   |
# Create semaphores      |
#                        |
# Fork task              | Task start
#                        |
# Wait for A             | Join A
#                        |
# Check child is running |
#                        |
# Join B                 | Wait for B
#                        |
# Continue tests         | Finish
#                        |
# Finish                 |
#
my $SEMAPHORE;
our $SEMAPHORE_POINT_A = 0;
our $SEMAPHORE_POINT_B = 1;


#
# Creates a new set of semaphores
#
sub semaphore_init {
	# Create a semaphore holding 2 values
	$SEMAPHORE = IPC::Semaphore->new(IPC_PRIVATE, 2, S_IRWXU | IPC_CREAT);
	isa_ok($SEMAPHORE, 'IPC::Semaphore');
	
	semaphore_reset();
}


#
# Resets the semaphores to 0
#
sub semaphore_reset {
	# Clear the semaphores
	my $return = $SEMAPHORE->setall(0, 0);
	ok(defined($return), "Semaphore cleared");
}


#
# Tell the other process that he can go futher since we have reached the rally
# point. We give the other process one more resource in order to go on.
#
sub semaphore_let_go {
	my ($who) = @_;
	$SEMAPHORE->op($who, 1, 0);
}


#
# Wait for the other process to reach his rally point and to let us go further.
# We remove a resource from this process, this will make us wait until the other
# process reaches the rally point.
#
sub semaphore_wait_for {
	my ($who) = @_;
	$SEMAPHORE->op($who, -1, 0);
}


# Return a true value
1;

