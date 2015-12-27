use strict;
use warnings;
use Test::CPANfile;
use Test::More;
 
cpanfile_has_all_used_modules(
    suggests     => 1,
    recommends   => 1,
);
done_testing;
