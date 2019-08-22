# All::Cores

All::Cores - Pure-perl module making it really easy to use all the cores on your CPU to parallel-process large amounts of data, collecting all the results into the parent process.

<!--- # NOTE: Use the below to generate the README.md doc file for github:-  (put an "e" in front of underscores to un-do Pod::Markdown escapes...
	perl -MPod::Markdown -e 'Pod::Markdown->new->filter(@ARGV)' lib/All/Cores.pm | sed -e 's:e&amp;lt;:<:g' | sed -e 's:\\\::g' > README.md     
\--->

# SYNOPSIS

    #!/usr/bin/perl -w
      
    use All::Cores;

    my $mp = new All::Cores();

    sub long_process { my($n)=@_; sleep(2); my %result=(pid=>$$,reply=>"Hello mummy, from child $n");return \%result; }

    foreach my $work (1..100) { 
      $mp->run(\&long_process,$work);   # forks() internally; on 24cpus, will block on work=25 until one of the children is done
      my $sneaky=$mp->peek_results();   # reference to the partially-constructed results array - this code only runs when any child exits.
    }

    my $ret=$mp->results();             # A 100-element array, NOT IN ANY PARTICULAR ORDER, containing the results.

# DESCRIPTION

This module determines how many CPUs you've got, then runs your workload on 
all of them at once, accumulating any results into the parent process.

## EXPORT

None by default.

## Notes

## new

Usage is

    my $mp = new All::Cores();

or

    my $mp = new All::Cores(4); # use exactly 4 CPUs for the work (not couting the parent)

## run

Calls specified sub (does not block - put in a loop to do many calls in parallel)

Usage is

    $mp->run(\&long_process);   # will call your &long_process() sub. This call returns immeidately (runs your code async in a fork()) if there are free CPUs, else it blocks.

or

    $mp->run(\&long_process,$work);     # Passes your supplied parms to your worker. e.g. calls &long_process($work);

## results

Get back the results from the children called via run()

Usage is

    my $ret=$mp->results();     # Gets back an array of all the results your workers returned

Note that we use JSON to encode those results and they get moved over an IPC socket to the parent process - so don't return anything that cannot be serialized.

## cpu\_count

Returns how many CPU cores are available

Usage is

    print $mp->cpu_count();

## peek\_results

Look at partial results from children who have finished now

Usage is

    my $sneaky=$mp->peek_results();     # Peek into the result array as it gets built

Note that $mp->run(\\&long_process); will block when all CPUs are busy, so you only get to peek at results when any child exits

It is safe to "pop" results off this - e.g. - to save to disk or whatever, thus making room in memory for long-running data stuff

## (internal) lock

Locks/unlocks access to a file (linux FIFO in our case) using flock(). Used internally.

    lock($fh, $op)

    $fh - file handle to be locked

    $op - type of lock (shared - LOCK_SH, exclusive - LOCK_EX, unlock - LOCK_UN)

While waiting for a lock, code can be executed inside the waiting loop.

# AUTHOR

This module was written by Chris Drake `cdrake@cpan.org`. \[[gitcnd](https://github.com/gitcnd)\]

# COPYRIGHT AND LICENSE

Copyright (c) 2019 Chris Drake. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.18.2 or,
at your option, any later version of Perl 5 you may have available.
