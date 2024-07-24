package Database::Async::Backoff::Exponential;

use strict;
use warnings;

# VERSION

use Object::Pad;
class Database::Async::Backoff::Exponential;
inherit Database::Async::Backoff;

use mro qw(c3);
use Future::AsyncAwait;
use List::Util qw(min);

Database::Async::Backoff->register(
    exponential => __PACKAGE__
);

ADJUST {
    $self->max_delay ||= 30;
    $self->initial_delay ||= 0.05;
}

async method next {
    return $self->delay = min(
        $self->max_delay,
        (2 * ($self->delay // 0))
         || $self->initial_delay
    );
}

1;
