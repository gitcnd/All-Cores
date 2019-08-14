#!/usr/bin/perl -w

# This does 100 iterations of sleep(2) - and takes 11 seconds to complete on a 24CPU machine.
  
use All::Cores;

my $mp = new All::Cores();

sub long_process { my($n)=@_; sleep(2); %result=(pid=>$$,reply=>"Hello mummy, from child $n");return \%result; }

foreach my $work (1..100) { 
  $mp->run(\&long_process,$work);   # forks() internally; on 24cpus, will block on work=25 until one of the children is done
  my $sneaky=$mp->peek_results();   # reference to the partially-constructed results array - this code only runs when any child exits.
}

my $ret=$mp->results();             # A 100-element array, NOT IN ANY PARTICULAR ORDER, containing the results.


print "\nret=$ret";
print "\nnret = $#{$ret}";
print "\nnret = " . join("\n", @{$ret});
