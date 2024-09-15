package Database::Async::ORM::Type;
use Full::Class qw(:v1);

# VERSION
# AUTHORITY

use List::Keywords qw(first);

field $schema:param:reader;
field $name:param:reader;
field $defined_in:param:reader;
field $description:param:reader;

field $type:param:reader;
field $basis:param:reader = undef;
field $is_builtin:param:reader;
field $values:param = [];
field $fields:param = [];

method values { $values->@* }
method fields { $fields->@* }

method qualified_name {
    $self->is_builtin
    ? $self->name
    : $self->schema->name . '.' . $self->name
}

1;

