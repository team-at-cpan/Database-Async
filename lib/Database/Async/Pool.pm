package Database::Async::Pool;
use Full::Class qw(:v1), extends => 'IO::AsyncX::Notifier';

# VERSION
# AUTHORITY

=head1 NAME

Database::Async::Pool - connection manager for L<Database::Async>

=head1 DESCRIPTION

=cut

use Database::Async::Backoff::Exponential;
use Database::Async::Backoff::None;

use Future;
use Syntax::Keyword::Try;
use List::UtilsBy qw(extract_by);

field $min:param:reader:Checked(Num) = 0;
field $max:param:reader:Checked(Num) = 1;

field $backoff:reader:Checked(Maybe(Isa(Database::Async::Backoff)));
field $pending_count:reader:Checked(Num) = 0;
field $count:reader:Checked(Num)         = 0;
field $waiting:Checked(ArrayRef)         = [];
field $ready:Checked(ArrayRef)           = [];
field $new_future;
field $request_engine_handler:param:mutator;
field $uri;

ADJUST {
    unless(blessed $backoff) {
        my $type = 'exponential';
        $type = $backoff if $backoff and not ref $backoff;
        $backoff = Database::Async::Backoff->instantiate(
            type          => $type,
            initial_delay => 0.010,
            max_delay     => 30,
            ($backoff && ref($backoff) ? %$backoff : ())
        );
    }
}

method register_engine ($engine) {
    --$pending_count;
    ++$count;
    $self
}

method unregister_engine ($engine) {
    try {
        $log->tracef('Engine is removed from the pool, with %d in the queue', 0 + $waiting->@*);
        my $addr = refaddr($engine);
        # This engine may have been actively processing a request, and not in the pool:
        # that's fine, we only remove if we had it.
        my $matching_count = () = extract_by { refaddr($_) == $addr } $ready->@*;
        $log->tracef('Removed %d engine instances from the ready pool', $matching_count);
        # Any engine that wasn't in the ready queue (`count`) was out on assignment
        # and thus included in `pending_count`
        if($matching_count) {
            --$count;
        } else {
            --$pending_count;
        }
        $log->infof('After cleanup we have %d count, %d pending, %d waiting', $count, $pending_count, 0 + $waiting->@*);
        $self->adopt_future($self->process_pending) if $waiting->@*;
    } catch ($e) {
        $log->errorf('Failed %s', $e);
    }
    $self
}

=head2 queue_ready_engine

Called when there's a spare engine we can put back in the pool.

=cut

method queue_ready_engine ($engine) {
    $log->tracef('Engine is now ready, with %d in the queue', 0 + $waiting->@*);
    return $self->notify_engine($engine) if $waiting->@*;
    push $ready->@*, $engine;
    $self
}

=head2 notify_engine

We call this internally to hand an engine over to the next
waiting request.

=cut

method notify_engine ($engine) {
    die 'unable to notify, we have no pending requests'
        unless my $f = shift $waiting->@*;
    $f->done($engine);
    return $self;
}

=head2 next_engine

Resolves to an engine. May need to wait if there are none available.

=cut

async method next_engine {
    $log->tracef('Have %d ready engines to use', 0 + $ready->@*);
    if(my $engine = shift $ready->@*) {
        return $engine;
    }
    push $waiting->@*, my $f = $self->new_future;
    await $self->process_pending;
    return await $f;
}

async method process_pending {
    my $total = $count + $pending_count;
    $log->tracef('Might request, current count is %d/%d (%d pending, %d active)', $total, $self->max, $pending_count, $count);
    await $self->request_engine unless $total >= $self->max;
    return;
}

method new_future ($label = 'pool') {
    (
        $new_future //= sub {
            Future->new->set_label($_[1])
        }
    )->($label)
}

async method request_engine {
    $log->tracef('Pool requesting new engine');
    ++$pending_count;
    my $delay = $self->backoff->next;
    if($delay) {
        my $f = $self->loop->delay_future(
            after => $delay
        );
        CANCEL { $f->cancel }
        await $f;
    }
    my $req = $request_engine_handler->();
    CANCEL { $req->cancel }
    await $req;
    $self->backoff->reset;
}

method _remove_from_loop ($loop) {
    $_->cancel for splice $waiting->@*;
    $self->unregister_engine($_) for splice $ready->@*;
    return $self->next::method($loop);
}

1;

=head1 AUTHOR

Tom Molesworth C<< <TEAM@cpan.org> >>

=head1 LICENSE

Copyright Tom Molesworth 2011-2024. Licensed under the same terms as Perl itself.

