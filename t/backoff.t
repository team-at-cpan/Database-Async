use strict;
use warnings;

use Test::More;
use Test::Fatal;

use Future::AsyncAwait;
use Database::Async::Backoff;

subtest 'default Database::Async::Backoff handling' => sub {
    my $backoff = new_ok('Database::Async::Backoff');
    is($backoff->next->get, 1, 'default 1 second backoff');
    is($backoff->next->get, 1, '1 second backoff consistently');
    done_testing;
};
subtest 'exponential Database::Async::Backoff handling' => sub {
    require Database::Async::Backoff::Exponential;
    my $backoff = new_ok('Database::Async::Backoff::Exponential' => [
        max_delay => 0.35,
    ]);
    is($backoff->max_delay, 0.35, 'can set max delay');
    is($backoff->next->get, 0.05, 'default 1 second backoff');
    is($backoff->next->get, 0.10, 'delay increases over time');
    is($backoff->next->get, 0.20, 'delay increases over time');
    is($backoff->next->get, 0.35, 'delay increases over time');
    is($backoff->next->get, 0.35, 'delay stabilises when it hits max value');
    done_testing;
};
done_testing;
