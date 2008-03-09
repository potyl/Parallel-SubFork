package Parallel::SubFork::Task;

=head1 NAME

Parallel::SubFork::Task - Run perl functions in forked processes. 

=head1 SYNOPSIS

	use Parallel::SubFork::Task;

	# Create and execute the task
	my $task = Parallel::SubFork::Task->new(\&job, @args);
	$task->execute();

	# Do the same in one step
	my $task2 = Parallel::SubFork::Task->start(\&job, @args);
	
	## From the main process, the one that actually started the tasks
	# Wait for the tasks to resume 
	$task->wait_for();
	$task2->wait_for();
	

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

A reference to a subroutine, this is the main code that's bein executed in a
different process.

=item args

The arguments that will be given to the subroutine being executed in a separated
process. The subroutine will receive the arguments through C<@_>.

=item pid

The PID of the process executing the subroutine, the child's PID.

=item exit_code

The exit code of the task, this is the value returned by C<exit>, C<_exit> or
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
	$self->{args} = \@args;
	
	return $self;
}



=head2 args

Returns the arguments that will be passed to the task when the main code will be
invoked. The arguments are returned as a list and not an array ref.

=cut

sub args {
	my $self = shift;
	
	my $args = $self->{args};
	my @args = defined $args ? @{ $args } : ();
	return @args;
}


=head2 execute

Executes the tasks (the code reference encapsulated by this task.) in a new
process. The code reference will be invoked with the arguments passed in the
constructor.

This method performs the actual fork and returns automatically for the invoker.
For the child process this is as far the the code will go. The invoker should
call L</wait_for> in order to wait for the child process to finish.

=cut

sub execute {
	my $self = shift;

	# Check that we don't run twice the same task
	if (defined $self->pid) {
		croak "Task already exectuted";
	}
	
	# Make sure that there's a code reference
	my $code = $self->code;
	if (! (defined $code and ref $code eq 'CODE')) {
		croak "Task requires a valid code reference (function)";
	}

	my $ppid = $$;

	# Fork a child
	my $pid = fork();
	
	# Check if the fork succeeded
	if (! defined $pid) {
		croak "Can't fork because: $!";
	}
	
	$self->_ppid($ppid);
	if ($pid == 0) {
		## CHILD part

		# Execute the main code
		my $return = 1;
		eval {
			$return = $code->($self->args);
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

Waits until the process that started this task has finished.

The exit status, that is the value passed to the C<exit> system call can be
inspected through the accessor L</exit_code> and the actual status, the value
returned in C<$?> by C<waitpid> can be accessed through the accessor L</status>.

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
		return;
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
			return;
		}
		elsif (WIFSIGNALED($status)) {
			$self->status($status);
			# WEXITSTATUS is only defined for WIFEXITED, here we assume an error
			$self->exit_code(1);
			return;
		}
	}
	
	return;
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
