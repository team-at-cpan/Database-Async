package Database::Async::ORM::Field;

use strict;
use warnings;

# VERSION

sub new {
    my ($class, %args) = @_;
    bless \%args, $class
}

sub table { shift->{table} }
sub name { shift->{name} }
sub type { shift->{type} }
sub nullable { shift->{nullable} }
sub default { shift->{default} }

1;

