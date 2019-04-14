package Database::Async::ORM::Schema;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class
}

sub name { shift->{name} }
sub defined_in { shift->{defined_in} }
sub description { shift->{description} }
sub tables { (shift->{tables} // [])->@* }
sub types { (shift->{types} // [])->@* }

1;

