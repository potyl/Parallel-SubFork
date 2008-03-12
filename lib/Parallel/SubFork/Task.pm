package Parallel::SubFork::Task;

=head1 NAME

Parallel::SubFork::Task - Run Perl functions in forked processes. 

=head1 SYNOPSIS

	use Parallel::SubFork::Task;
	
	# Run a some arbitrary Perl code in a separated process
	my $task = Parallel::SubFork::Task->start(\&job, @args);
	$task->wait_for();
	
	# Create and execute the task (same as above)
	my $task2 = Parallel::SubFork::Task->new(\&job, @args);
	$task2->execute();
	$task2->wait_for();
	
	# Access any of the properties
	printf "PID of task was %s\n", $task->pid;
	printf "Args of task where %s\n", join(", ", $task->args);
	printf "Exit code: %d\n", $task->exit_code;

=head1 DESCRIPTION

This module provides a simpler way to run arbitrary Perl code in a different
process. This module consists of a fancy wrapper over the system calls L<fork>
and L<waitpid>. The idea is to execute any standard Perl function in a different
process without any of the inconveniences of managing the forks by hand.

=head1 TASK

This module is used to encapsulate a task, i.e. the function to be executed in
a different process and it's arguments. In a nutshell a task consists of a
reference to a Perl function (C<\&my_sub>) or a closure (C<sub { 1; }>), 
also known as an anonymous subroutine, and optionally the arguments to provide
to that function.

A task also stores some runtime properties such as the PID of the process that 
executed the code, the exit code and the exit status of the process. These
properties can then be inspected by the parent process through their dedicated
accessors.

There's also some helper methods that are used to create the child process and
to wait for it to resume.

=head1 PROCESSES

Keep in mind that the function being executed is run in a different process.
This means that any modification performed within that function will only affect
the process running the task. This is true even for global variables. All data
exchange or communication between the parent the child process has to be
implemented manually through standard I<inter process communication> (IPC)
mechanisms (see L<perlipc>).

The child process used to executes the Perl subroutines has it's environment
left unchanged. This means that all file descriptors, signal handlers and other
resources are still available. It's up to the subroutine to prepare it self a
proper environment.

=head1 RETURN VALUES

The subroutine return's value will be used as the process exit code, this is the
only thing that the invoking process will be able to get back from the task
without any kind of IPC. This means that the return value should be an integer.
Furthermore, since the return value is used as an exit value in this case C<0>
is considered as successful execution while any other value is usually
interpreted as an error.

=head1 EXIT

The subroutine is free to raise any exceptions through L<die> or any similar
mechanism. If an error is caught by the framework it will be interpreted as an
error and an appropriate exit value will be used.

If the subroutine needs to resume it's execution through a the system call
L<exit> then consider instead using C<_exit> as defined in the module L<POSIX>.
This is because L<exit> not only terminates the current process but it performs
some cleanup such as calling the functions registered with C<atexit> and flush
all stdio streams before finishing the process. Normally, only the main process
should call L<exit>, in the case of a fork the children should finish their execution through C<POSIX::_exit>.

=head1 PROCESS WAIT

Waiting for process to finish can be problematic. There are multiple ways for waiting for processes to resume. Each having it's advantages and disadvantages.

The easiest way is to register a signal handler for C<CHLD> signal. This has the
advantage of receiving the child notifications as they happen, the disadvantage
is that there's no way to control for which children the notifications will
happen. This is quite inconvenient because a lot of the nice built-in functions
and operators in Perl such as C<`ls`>, L<system> and even L<open> (when used in
conjunction with a C<|>) use child processes for their tasks and this could
potentially interfere with such utilities.

Another alternative is to wait for all processes launched but this can also
interfere with other processed launched manually through L<fork>.

Finally, the safest way is to wait explicitly B<only> for the processes that we
know to have started and nothing else. This there will be no interference with
the other processes. This is exactly the approach used by this module.

=head1 METHODS

A task defines the following methods:

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
our $VERSION = '0.04';


=head2 start

Creates and executes a new task, this is simply a small shortcut for starting
new tasks.

In order to manage tasks easily consider using use the module
L<Parallel::SubFork> instead.

Parameters:

	$code: the code reference to execute in a different process.
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

Creates a new task, this is simply a constructor and the task will not be
started yet.

The task can latter by started through a call to L</"execute">.

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

=head2 code

Accessor to the function (code reference) that will be executed in a different
process. This is what the child process will execute. 

This function is expected to return C<0> for success and any other integer to
indicate a failure. The function is free to raise any kind of exception as the
framework will catch all exceptions and return an error value instead.

The function will receive it's parameters normally through the variable C<@_>.

=head2 pid

The PID of the process executing the subroutine, the child's PID.

=head2 exit_code

The exit code of the task, this is the value returned by L<exit>, 
C<POSIX::_exit> or C<return>.

=head2 status

The exit code returned to the parent process as described by C<wait>. The status
code can be inspected through the L<"POSIX/WAIT"> macros .


=head2 args

The arguments that will be given to the subroutine being executed in a separated
process. The subroutine will receive this very same arguments through C<@_>.

This method always return it's values as a list and not as an array ref.

=cut

sub args {
	my $self = shift;
	
	my $args = $self->{args};
	my @args = defined $args ? @{ $args } : ();
	return @args;
}


=head2 execute

Executes the tasks (the code reference encapsulated by this task) in a new
process. The code reference will be invoked with the arguments passed in the
constructor.

This method performs the actual fork and returns automatically for the invoker,
while the child process will start to execute the code in defined in the code
reference. Once the subroutine has finished the child process will resume right
away.

The invoker (the parent process) should call L</wait_for> in order to wait for
the child process to finish and obtain it's exit value.

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

Waits until the process running the task (the code reference) has finished.

The exit status of the process can be inspected through the accessor 
L</"exit_code"> and the actual status, the value returned in C<$?> by L<waitpid>
can be accessed through the accessor L</"status">.

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

=head1 NOTES

The API is not yet frozen and could change as the module goes public.

=head1 SEE ALSO

Take a look at L<POE> for asynchronous multitasking and networking.

=head1 AUTHOR

Emmanuel Rodriguez, E<lt>emmanuel.rodriguez@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Emmanuel Rodriguez

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.

=cut
