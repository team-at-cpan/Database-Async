package Database::Async::Backoff::Exponential;
use Full::Class qw(:v1), extends => 'Database::Async::Backoff';

# VERSION
# AUTHORITY

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
