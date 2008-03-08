package Parallel::SubFork;

=head1 NAME

Parallel::SubFork - Run perl functions in forked processes. 

=head1 SYNOPSIS

	use Parallel::SubFork;
	my $manager = Parallel::SubFork->new();
	
	# Start two pararallel tasks
	$manager->start(sub { sleep 10; print "Done\n" });
	$manager->start(\&callback, @args);
	
	# Wait for all tasks to resume
	$manager->wait_for_all();
	
	# Loop through all tasks
	foreach my $task ($manager->tasks) {
		# Access any of the properties
		printf "Task with PID %d resumed\n", $task->pid;
		printf "Exist status: %d, exit code: %d\\n", $task->status, $task->exit;
		printf "Args of task where: %s\n", join(', ', $task->args);
		print "\n";
	}

=head1 DESCRIPTION

This module provides a simple wrapper over the system calls C<fork> and C<wait>
that can be used to execute some tasks in parallel. The idea is to isolate the
tasks to be excecute in functions or closures and to perform this tasks in a
separated process.

=head1 TASKS

A task is simply a Perl function or a closure that will get executed in a
different process. This module will take care of creating and managing the new
processes. All that's left is to code the logic of each task and to provide the
proper IPC mechanism if needed.

A task will run in it's own process thus it's important to understand that all
modifications to variables within the tasks even global variables will have no
impact on the parent processs. Communication or data exchange between the task 
and the dispatcher (the code that started the task) has to be performed through
standard IPC mechanisms. For futher details on how to establish different
communication channels referer to the documentation of L<perlipc>.

Since a task is running within a process it's expected that the task will return
an exit code and not a true value in the I<Perl> sense. The return value will be
used as the exit code of the process that's running the task.

=head1 METHODS

The module defines the following methods:

=cut

use strict;
use warnings;

use Carp;
use POSIX qw(_exit);

use Parallel::SubFork::Task;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(
	qw(
		tasks
		_dispatcher_pid
	)
);


# Version of the module
our $VERSION = '0.01';


=head2 new

Creates a new C<Parallel::SubFork>.

=cut

sub new {

	# Arguments
	my $class = shift;
	
	# Create a blessed instance
	my $self = bless {}, ref($class) || $class;
	
	# The list of children spawned
	$self->tasks([]);
	
	# The PID of the dispacher
	$self->_dispatcher_pid($$);

	return $self;
}


=head2 start

Starts the execution of a new task in a different process. A taks consists of a
code reference (a closure or a reference to a subroutine) and of a arguments
list.

This method will actually fork a new process and execute the given code
reference in the child process. For the parent processs this method will return
automatically. The child process will start executing the code reference with
the given arguments.

The parent process, the one that started the task should wait for the child
process to resume. The child process can only 


This doesn't mean that the child process is over, instead the 


For the parent process this method is non blocking and will return automatically.
For the new child this is as far as the code goes

=cut

sub start {

	# Arguments
	my $self = shift;
	my ($code, @args) = @_;

	# Stop if this is not the dispatcher
	$self->_assert_is_dispatcher();


	# Prepare the task
	my $task = Parallel::SubFork::Task->new(
		{
			code => $code,
			args => \@args,
		}
	);


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
			$return = $task->_execute();
		};
		if (my $error = $@) {
			carp "Child executed with errors: ", $error;
		}
		
		# This is as far as the kid gets if the callback hasn't called exit we must doit
		_exit($return);
	}
	else {
		## PARENT part
		$task->pid($pid);
		push @{ $self->{tasks} }, $task;
	}
	
	return $task;
}


=head2 wait_for_all

Starts the execution of a new task in a different process. A taks consists of a
code reference (a closure or a reference to a subroutine) and of a arguments
list.

This method will actually fork a new process and execute the given code
reference in the child process. For the parent processs this method will return
automatically. The child process will start executing the code reference with
the given arguments.

The parent process, the one that started the task should wait for the child
process to resume. The child process can only 


This doesn't mean that the child process is over, instead the 


For the parent process this method is non blocking and will return automatically.
For the new child this is as far as the code goes

=cut

sub wait_for_all {
	my $self = shift;

	$self->_assert_is_dispatcher();

	foreach my $task (@{ $self->tasks }) {
		$task->wait_for();
	}
}


=head2 tasks

Returns the tasks started so far by this instance. This method returns a list
and not an array ref.

=cut

sub tasks {
	my $self = shift;

	my $tasks = $self->{tasks};
	my @tasks = defined $tasks ? @{ $tasks} : ();
	return @tasks;
	
	if (defined $tasks) {
		return wantarray ? @{ $tasks } : scalar @{ $tasks };
	}
	
	# NOTE: If there are not tasks yet we must return VOID in list context which
	#       Perl will transform into an empty list. Otherwise, returning $tasks
	#       will return undef, which in list context is true because it will be
	#       transformed into a list of one undef element.
	
	return if wantarray;
	return 0;
}


=head2 _assert_is_dispatcher

Used to check if the current process is the same one that invoked the
constructor.

This is required as only the dispatcher process is allowed to start and wait for
tasks.

=cut

sub _assert_is_dispatcher {
	my $self = shift;
	return if $self->_dispatcher_pid == $$;
	croak "Process $$ is not the main dispatcher";
}


# Return a true value
1;


=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Emmanuel Rodriguez, E<lt>emmanuel.rodriguez@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Emmanuel Rodriguez

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
