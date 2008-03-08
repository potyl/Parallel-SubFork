package Parallel::SubFork::Task;

=head1 NAME

Parallel::SubFork::Task - Representation of a Task (a subprocess).

=head1 SYNOPSIS

	use Parallel::SubFork::Task;
	my $task = Parallel::SubFork::Task->new(
		{
			code => sub { print "A new process $$: @_"; },
			args => ['one', 'two'],
		}
	);

	## From another process (fork)
	# Execute the task
	$task->execute();
	
	
	## From the main process
	# Wait for the tasks to resume 
	$task->wait();

	# Access any of the properties
	printf "PID of task was %s\n", $task->pid;
	printf "Args of task where %s\n", join ", ", $task->args;

=head1 DESCRIPTION

This module represents a task, a code reference (a subroutine or a closure) that
will be executed with some predefined arguments.

A tasks consists of a reference to a subroutine and it's arguments that will be invoked
by a forked child. The task will also store some runtinme properties such as the PID,
exit code and so on. This properties can then be inspected by the parent process.

This class is just a simple wrapper over the properties defined in a task:

=over

=item code

A reference to a subroutine, this is the main code that's bein executed.

=item args

The arguments that will be given to the subroutine through C<@_>.

=item pid

The PID of the process executing the subroutine, the child PID.

=item exit_code

The exit code of the task, this is the value returned by C<exit> or C<_exit> or
C<return>.

=item status

The exit code returned to the parent process as described by C<wait>.

=back

=head1 METHODS

This module defines the following methods:

=head2 new

Creates a new instance with the given arguments.
Expects as arguments an hash of the key/value pairs 
to affect to the new object.

=cut


use strict;
use warnings;

use POSIX qw(WIFEXITED WEXITSTATUS WIFSIGNALED);

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(
	qw(
		pid
		code
		exit_code
		status
	)
);

# Version of the module
our $VERSION = '0.01';


=head2 args

Returns the arguments that will be passed to the task when the main code will be
invoked. The arguments are returned as a list and not an array ref. If there are
no arguments nothing will be returned.

=cut

sub args {
	my $self = shift;
	
	# Save the arguments if there are present
	$self->{args} = \@_ if @_;
	
	# NOTE: If the arguments are not yet set we must return VOID which 
	#       Perl will transform into an empty list. Otherwise, returning
	#       $self->{args}  will return undef, which in list context is true
	#       because it will be transformed into a list of one undef element.
	return unless defined $self->{args};
	
	return @{ $self->{args} };
}



=head2 execute

Executes the tasks, thus the code reference encapsulated by this task. The code
reference will be invoked with the arguments passed in the constructor.

This method will return whatever the code reference returns. This is expected to
be a value that will be passed to C<exit>.

B<NOTE> This method whould never be invoked directly.

=cut

sub _execute {
	my $self = shift;
	return $self->code->($self->args);
}


=head2 wait_for

Waits until the process that started this task has finished. This method returns
the exit status, that is the value passed to the C<exit> system call and not the
value returned by C<wait>.

=cut

sub wait_for {
	my $self = shift;

	my $pid = $self->pid;
	return unless defined $pid and $pid > 0;
	
	while (1) {
		
		# Wait for the specific PID
		my $result = waitpid($pid, 0);
		if ($result == -1) {
			# No more processes to wait for, but we didn't find our PID
			return 1;
		}
		elsif ($result == 0) {
			# Still running, wait some more
			next;
		}
		elsif ($result != $pid) {
			# Strange we got another PID than ours
			return 1;
		}
		
		# Now we got a call to wait, this doesn't mean that the child died! It just
		# means that the child got a state change (the child terminated; the child
		# was stopped by a signal;  or  the  child was  resumed  by a signal). Here
		# we must check if the process finished properly otherwise we must continue
		# waiting for the end of the process.
		my $status = $?;
		if (WIFEXITED($status)) {
			$self->status($status);
			$self->exit_code(WEXITSTATUS($status));
		}
		elsif (WIFSIGNALED($status)) {
			$self->status($status);
			# WEXITSTATUS is only defined for WIFEXITED, here we assume an error
			$self->exit_code(1);
		}
	}
}


# Return a true value
1;


=head1 AUTHOR

Emmanuel Rodriguez, E<lt>emmanuel.rodriguez@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Emmanuel Rodriguez

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
