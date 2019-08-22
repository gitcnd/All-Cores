package All::Cores;

use strict;
use warnings;

=head1 All::Cores

All::Cores - Pure-perl module making it really easy to use all the cores on your CPU to parallel-process large amounts of data, collecting all the results into the parent process.

e<!--- # NOTE: Use the below to generate the README.md doc file for github:-  (put an "e" in front of underscores to un-do Pod::Markdown escapes...
	perl -MPod::Markdown -e 'Pod::Markdown->new->filter(@ARGV)' lib/All/Cores.pm | sed -e 's:e&lt;:<:g' | sed -e 's:e\\::g' > README.md     
--->

=head1 SYNOPSIS

    #!/usr/bin/perl -w
      
    use All::Cores;

    my $mp = new All::Cores();

    sub long_process { my($n)=@_; sleep(2); my %result=(pid=>$$,reply=>"Hello mummy, from child $n");return \%result; }

    foreach my $work (1..100) { 
      $mp->run(\&long_process,$work);	# forks() internally; on 24cpus, will block on work=25 until one of the children is done
      my $sneaky=$mp->peek_results();	# reference to the partially-constructed results array - this code only runs when any child exits.
    }

    my $ret=$mp->results();		# A 100-element array, NOT IN ANY PARTICULAR ORDER, containing the results.


=head1 DESCRIPTION

This module determines how many CPUs you've got, then runs your workload on 
all of them at once, accumulating any results into the parent process.


=head2 EXPORT

None by default.


=head2 Notes

=cut

require Exporter;

our @ISA = qw(Exporter);
our($VERSION)='1.02';
our($UntarError) = '';

our %EXPORT_TAGS = ( 'all' => [ qw( ) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw( );

use strict;
use warnings;		# same as -w switch above
use Fcntl qw(:DEFAULT :flock);
use Socket;
use IO::Handle;  # thousands of lines just for autoflush :-(
use POSIX ":sys_wait_h";
use IO::Select; 
use Sys::Info; use Sys::Info::Constants qw( :device_cpu );
use JSON::XS;


=head2 new

Usage is

    my $mp = new All::Cores();

or

    my $mp = new All::Cores(4);	# use exactly 4 CPUs for the work (not couting the parent)

=cut

# Count CPUs, open IPC pair, and prep to do forking.
sub new {
  my $class = shift;
  my $this={};
  $this->{ncpus}=shift;
  $this->{forks}=0;

  if(!$this->{ncpus}) { # Determine how many CPUs we have got...
    my $info = Sys::Info->new;
    my $cpu  = $info->device( CPU => my %options );
     $this->{ncpus}=$cpu->count || 1;
  }
  #Old way: my @ncpus=`grep -P 'processor\\s+:\\s+\\d+\$' /proc/cpuinfo`; my $ncpus=1+$#ncpus;
  #dbg: print "Process ID: $$ - we have $this->{ncpus} CPUs\n"; # . scalar($cpu->identify) . "\n";

  socketpair(my $CHILD, my $PARENT, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ||  die "socketpair: $!";
  $CHILD->autoflush(1); $PARENT->autoflush(1);
  my $sel = IO::Select->new;
  $sel->add($CHILD);
  $this->{PARENT}=$PARENT;
  $this->{CHILD}=$CHILD;
  $this->{sel}=$sel;
  my @results;
  $this->{results}=\@results;

  bless $this,$class;
  return $this;
} # new



################################################################################

=head2 run

Calls specified sub (does not block - put in a loop to do many calls in parallel)

Usage is

    $mp->run(\&long_process);	# will call your &long_process() sub. This call returns immeidately (runs your code async in a fork()) if there are free CPUs, else it blocks.

or

    $mp->run(\&long_process,$work);	# Passes your supplied parms to your worker. e.g. calls &long_process($work);

=cut

sub run {
  my $this = shift;
  my $subref = shift;

  while($this->{forks}>=$this->{ncpus}) { # all busy
    my $pid=&fingertwiddle($this); # Wait for a child to exit, while reading from kid sockets
  }

  my $pid = fork; die 'Could not fork()' if(!defined $pid);;
  if($pid) {
    $this->{forks}++;
    #dbg: print "In the parent process PID ($$), Child pid: $pid Num of fork child processes: $this->{forks}, upto=$_[0]\n";
  } else {
    #dbg: print "In the child process PID ($$)\n"; 
    my $ret=&{$subref}(@_);	# run the sub, push the results onto our stack
    my($PARENT,$CHILD)=($this->{PARENT},$this->{CHILD});
    &lock($PARENT,LOCK_EX);
    print $PARENT encode_json($ret) . "\n";
    close($PARENT); close($CHILD);
    exit;
  }
} # run



################################################################################

=head2 results

Get back the results from the children called via run()

Usage is

    my $ret=$mp->results();	# Gets back an array of all the results your workers returned

Note that we use JSON to encode those results and they get moved over an IPC socket to the parent process - so don't return anything that cannot be serialized.

=cut

# Get back the results from the children
sub results {
  my $this = shift;
  while($this->{forks}) {
    my $pid=&fingertwiddle($this); # Wait for a child to exit, while reading from kid sockets
  }
  sleep(1);&fingertwiddle($this); # Get the last stragglers;
  #dbg: print "Parent ($$) ending\n";
  return $this->{results};
} # results



################################################################################

=head2 cpu_count

Returns how many CPU cores are available

Usage is

    print $mp->cpu_count();

=cut

sub cpu_count {
  my $this = shift;
  return $this->{ncpus}
} # 




################################################################################

=head2 peek_results

Look at partial results from children who have finished now

Usage is

    my $sneaky=$mp->peek_results();	# Peek into the result array as it gets built

Note that $mp->run(\&longe_process); will block when all CPUs are busy, so you only get to peek at results when any child exits

It is safe to "pop" results off this - e.g. - to save to disk or whatever, thus making room in memory for long-running data stuff

=cut

sub peek_results {
  my $this = shift;
  &fingertwiddle($this);
  return $this->{results};
} # peek_results


sub fingertwiddle {
  my $this = shift;
  my $pid = waitpid(-1, WNOHANG);
  if($pid>0) {
    #dbg: print "Parent saw $pid exiting\n";
    $this->{forks}--;
  } else {
    if (my @ready = $this->{sel}->can_read(0)) {  # beware of signal handlers
      #dbg: print "SKT: " . join("^",@ready);
      my $maxread=256 * 1024000-3; # a very big buffer, which we hope no sender will ever exactly match (coz it might block trying to read non-existent more bytes)
      my $ret=''; my $rv; my $CHILD=$this->{CHILD};
      do {
        my $buff;
        $rv = sysread $CHILD, $buff, $maxread;
        $ret.=$buff;
      } while($rv==$maxread);
      foreach(split(/\n/,$ret)){my $s;eval('$s=decode_json($_)'); push @{$this->{results}},$s;}
      #dbg: print "r= " . $#{$this->{results}} . "got:-\n$ret";

    }
    #print "Parent idle...\n"; select(undef,undef,undef,0.2);
  }
  return $pid;
} # fingertwiddle



################################################################################

=head2 (internal) lock

Locks/unlocks access to a file (linux FIFO in our case) using flock(). Used internally.

  lock($fh, $op)

  $fh - file handle to be locked

  $op - type of lock (shared - LOCK_SH, exclusive - LOCK_EX, unlock - LOCK_UN)

While waiting for a lock, code can be executed inside the waiting loop.

=cut

sub lock { # locking sub to provide concurent access
  my ($fh, $op) = @_;

  if (not defined (fileno($fh))) {
    die "Open file before locking"; 
  } # open the file handle if file handle is closed

  my($noloop)=0;

  while ((!flock($fh, $op ))&&($noloop++<100)) {
    select(undef,undef,undef,0.001) if($noloop>10);
    select(undef,undef,undef,0.01) if($noloop>20);
    select(undef,undef,undef,0.1) if($noloop>50);
    die "elog problem $!" if($noloop>90);
    # Wait to aquire lock
    # Code can be executed here while we wait for the lock
  }
} # lock



1;

__END__

=head1 AUTHOR

This module was written by Chris Drake F<cdrake@cpan.org>. e[[gitcnd](https://github.com/gitcnd)]


=head1 COPYRIGHT AND LICENSE

Copyright (c) 2019 Chris Drake. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.2 or,
at your option, any later version of Perl 5 you may have available.

=cut

