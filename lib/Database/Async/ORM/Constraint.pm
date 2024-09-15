package Database::Async::ORM::Constraint;
use Full::Class qw(:v1);

# VERSION
# AUTHORITY

field $table:param:reader;
field $name:param:reader;
field $type:param:reader;
field $fields:param = [];
field $references:param = undef;
field $deferrable:param = 0;
field $initially_deferred:param = 0;

method is_deferrable { !!$deferrable }
method is_deferred { !!$initially_deferred }

method fields {
    map { $self->table->field_by_name($_) } ($fields //= [])->@*
}

method references {
    $self->table->schema->table_by_name($references->{table});
}

1;

