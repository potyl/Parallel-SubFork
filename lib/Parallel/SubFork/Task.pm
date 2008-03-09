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

use POSIX qw(
	WIFEXITED
	WEXITSTATUS
	WIFSIGNALED
	getppid
	_exit
);

use Carp;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(
	qw(
		_ppid
		pid
		code
		exit_code
		status
	)
);

# Version of the module
our $VERSION = '0.01';


=head2 start

Creates and executes a new task, this is simply a small shortcut for starting
new tasks.

In order to manage tasks easily consider using use the module
L<Parallel::SubFork> instead.

Parameters:
	$code: the code reference to execute.
	@args: the arguments to pass to the code reference (optional).

=cut

sub start {
	my $class = shift;
	my ($code, @args) = @_;
	croak "First parameter must be a code reference" unless ref $code eq 'CODE';
	
	my $task = $class->new($code, @args);
	$task->execute();

	return $task;
}


=head2 new

Creates a new task, this is simply a constructor. The task it not started yet.
The task is only started through a call to L<execute>.

In order to manage tasks easily consider using use the module
L<Parallel::SubFork> instead.

Parameters:
	$code: the code reference to execute.
	@args: the arguments to pass to the code reference (optional).

=cut

sub new {
	my $class = shift;
	my ($code, @args) = @_;
	croak "First parameter must be a code reference" unless ref $code eq 'CODE';
	
	# Create a blessed instance
	my $self = bless {}, ref($class) || $class;
	$self->code($code);
	$self->args(@args);
	
	# The current process ID will be the parent
	$self->_ppid($$);
	
	return $self;
}



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

Executes the tasks (the code reference encapsulated by this task.) in a new
process. The code reference will be invoked with the arguments passed in the
constructor.

This method performs the actual fork and returns automatically for the invoker.
For the child process this is as far the the code will go.

=cut

sub execute {
	my $self = shift;

	$self->_ppid($$);

	# Fork a child
	my $pid = fork();
	
	# Check if the fork succeeded
	if (! defined $pid) {
		croak "Can't fork because: $!";
	}
	elsif ($pid == 0) {
		## CHILD part

		# Execute the main code
		my $return = 1;
		eval {
			$return = $self->code->($self->args);
		};
		if (my $error = $@) {
			carp "Child executed with errors: ", $error;
		}
		
		# This is as far as the kid gets if the callback hasn't called exit we must doit
		_exit($return);
	}
	else {
		## PARENT part
		$self->pid($pid);
	}
}


=head2 wait_for

Waits until the process that started this task has finished. This method returns
the exit status, that is the value passed to the C<exit> system call and not the
value returned in C<$?> by C<waitpid>.

=cut

sub wait_for {
	my $self = shift;

	my $pid = $self->pid;
	return unless defined $pid and $pid > 0;
	if (! (defined $pid and $pid > 0) ) {
		croak "Task isn't started";
	}
	
	# Only the real parent can wait for the child
	if ($self->_ppid != $$) {
		croak "Only the parent process can wait for the task";
	}
	
	# Check if the task was already waited for
	if (defined $self->status) {
		return $self->exit_code;
	}
	
	while (1) {
		
		# Wait for the specific PID
		my $result = waitpid($pid, 0);
		if ($result == -1) {
			# No more processes to wait for, but we didn't find our PID
			croak "No more processes to wait PID $pid not found";
		}
		elsif ($result == 0) {
			# Still running, keep waiting
			next;
		}
		elsif ($result != $pid) {
			# Strange we got another PID than ours
			croak "Got a status change for PID $result while waiting for PID $pid";
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
			last;
		}
		elsif (WIFSIGNALED($status)) {
			$self->status($status);
			# WEXITSTATUS is only defined for WIFEXITED, here we assume an error
			$self->exit_code(1);
			last;
		}
	}
	
	return $self->exit_code;
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
