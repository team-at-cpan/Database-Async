package Database::Async::ORM::Extension;
use Full::Class qw(:v1);

# VERSION
# AUTHORITY

field $name:param:reader;
field $defined_in:param:reader;
field $description:param:reader;
field $optional:param:reader;

method is_optional { $optional ? 1 : 0 }

1;

