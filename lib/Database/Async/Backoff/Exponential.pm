package Database::Async::Backoff::Exponential;

use strict;
use warnings;

# VERSION

sub new {
    my ($class, %args) = @_;
    bless \%args, $class
}


1;
