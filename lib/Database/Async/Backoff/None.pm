package Database::Async::Backoff::None;

use strict;
use warnings;

# VERSION

use Object::Pad;
class Database::Async::Backoff::None;
inherit Database::Async::Backoff;

use mro qw(c3);

Database::Async::Backoff->register(
    none => __PACKAGE__
);

sub next { 0 }

1;
