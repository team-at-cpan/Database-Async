package Database::Async::ORM::Table;
use Full::Class qw(:v1);

# VERSION
# AUTHORITY

use List::Keywords qw(first);

field $schema:param:reader;
field $name:param:reader;
field $defined_in:param:reader;
field $description:param:reader;
field $tablespace:param:reader;

field $parents:param = [];
field $fields:param = [];
field $constraints:param = [];
field $primary_keys:param = [];

method parents { $parents->@* }
method fields { $fields->@* }
method constraints { $constraints->@* }

method foreign_keys {
    grep { $_->type eq 'foreign_key' } $self->constraints
}

method primary_keys {
    map { $self->field_by_name($_) } $primary_keys->@*
}

method field_by_name ($name) {
    return first { $_->name eq $name } $self->fields;
}

method qualified_name {
    $self->schema->name . '.' . $self->name
}

1;

