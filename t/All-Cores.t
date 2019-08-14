# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl IO-Uncompress-Untar.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More;
BEGIN { use_ok('All::Cores') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


use All::Cores;

my $mp = new All::Cores();

sub long_process { my($n)=@_; sleep(1); my %result=(pid=>$$,reply=>"Hello mummy, from child $n");return \%result; }

foreach my $work (1..100) { 
  $mp->run(\&long_process,$work);   # forks() internally; on 24cpus, will block on work=25 until one of the children is done
  my $sneaky=$mp->peek_results();   # reference to the partially-constructed results array - this code only runs when any child exits.
}

my $ret=$mp->results();             # A 100-element array, NOT IN ANY PARTICULAR ORDER, containing the results.

ok($#{$ret}==99);

done_testing();

  # or
  #          use Test::More;   # see done_testing()
  #
  #                   require_ok( 'Some::Module' );
  #
  #                            # Various ways to say "ok"
  #                                     ok($got eq $expected, $test_name);
