package Database::Async::Engine::Empty;
use Full::Class qw(:v1), extends => 'Database::Async::Engine';

# VERSION
# AUTHORITY

=head1 NAME

Database::Async::Engine::Empty - a database engine that does nothing useful

=head1 DESCRIPTION

=cut

Database::Async::Engine->register_class(
    empty      => 'Database::Async::Engine::Empty',
);

my %queries = (
    q{select 1} => {
        fields => [ '?column?' ],
        rows => [
            [ '1' ]
        ],
    },
);

1;

