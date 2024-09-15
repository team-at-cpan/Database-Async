use Full::Script qw(:v1);
use Test::More;
use Test::Fatal;

use Database::Async;
use Database::Async::Engine::Empty;

# If we have ::TAP, use it - but no need to list it as a dependency
eval {
    require Log::Any::Adapter;
    Log::Any::Adapter->import(qw(TAP));
};

subtest 'basic Database::Async::Pool handling' => sub {
    my $pool = new_ok('Database::Async::Pool');
    done_testing;
} if 0;

subtest 'Database::Async::Pool instantiation via Database::Async' => sub {
    my $db = new_ok(
        'Database::Async', [
            type => 'empty',
            pool => {
                backoff => 'none',
                min     => 0,
                max     => 5
            }
        ]
    );
    my $pool = $db->pool;
    isa_ok($pool, 'Database::Async::Pool');
    is($pool->min, 0, 'min value passed through from constructor');
    is($pool->max, 5, 'max value passed through from constructor');

    my $engine = Database::Async::Engine::Empty->new;
    is($pool->count, 0, 'no engines in pool yet');
    $pool->register_engine($engine);
    is($pool->count, 1, 'now have one engine in pool');
    $pool->queue_ready_engine($engine);
    Scalar::Util::weaken($engine);
    is(exception {
        isa_ok(my $f = $pool->next_engine, 'Future');
        ok($f->is_ready, 'the engine is available immediately');
        is($f->get, $engine, 'requested engine matches ready one');
        my $requested = 0;
        dynamically $pool->request_engine_handler = async sub {
            ++$requested;
        };
        isa_ok(my $next = $pool->next_engine, 'Future');
        is($requested, 1, 'asked for one engine');
        ok(!$next->is_ready, 'still pending on second request') or note diag $next->state;
        note explain [ $next->failure ] if $next->is_failed;
    }, undef, 'can request an engine');
    is($engine, undef, 'engine was released when no longer used');
    done_testing;
};
done_testing;

