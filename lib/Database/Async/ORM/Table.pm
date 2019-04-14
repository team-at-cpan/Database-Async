package Database::Async::ORM::Table;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    bless \%args, $class
}

sub schema { shift->{schema} }
sub name { shift->{name} }
sub defined_in { shift->{defined_in} }
sub description { shift->{description} }
sub tablespace { shift->{tablespace} }
sub parents { (shift->{parents} //= [])->@* }
sub fields { (shift->{fields} //= [])->@* }

1;

