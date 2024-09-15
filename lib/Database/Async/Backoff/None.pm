package Database::Async::Backoff::None;
use Full::Class qw(:v1), extends => 'Database::Async::Backoff';

# VERSION
# AUTHORITY

Database::Async::Backoff->register(
    none => __PACKAGE__
);

sub next { 0 }

1;
