package Database::Async::Backoff;

use strict;
use warnings;

# VERSION

use Object::Pad;
class Database::Async::Backoff;

=head1 NAME

Database::Async::Backoff - support for backoff algorithms in L<Database::Async>

=head1 DESCRIPTION

=cut

use Future::AsyncAwait;

my %class_for_type;

field $initial_delay : mutator : param = 0;
field $max_delay : mutator : param = 30;
field $delay : mutator : param = 0;

async method next ($code = undef) {
    return $self->delay ||= 1;
}

async method reset {
    $self->delay = 0;
    $self
}

sub register {
    my ($class, %args) = @_;
    for my $k (keys %args) {
        $class_for_type{$k} = $args{$k}
    }
    $class
}

sub instantiate {
    my ($class, %args) = @_;
    my $type = delete $args{type}
        or die 'backoff type required';
    my $target_class = $class_for_type{$type}
        or die 'unknown backoff type ' . $type;
    return $target_class->new(%args);
}

1;

