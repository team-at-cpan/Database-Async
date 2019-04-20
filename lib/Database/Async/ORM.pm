package Database::Async::ORM;

use strict;
use warnings;

# VERSION

=head1 NAME

Database::Async::ORM - provides object-relational features for L<Database::Async>

=head1 SYNOPSIS

 use 5.020;
 use IO::Async::Loop;
 use Database::Async::ORM;
 my $loop = IO::Async::Loop->new;
 $loop->add(
  my $orm = Database::Async::ORM->new
 );

 # Load schemata directly from the database
 $orm->load_from($db)
  ->then(sub {
   say 'We have the following tables:';
   $orm->tables
       ->map('name')
       ->say
       ->completed
  })->get;

 # Load schemata from a hashref (e.g. pulled
 # from a YAML/JSON/XML file or API)
 $orm->load_from({ ... })
  ->then(sub {
   $orm->apply_to($db)
  })->then(sub {
   say 'We have the following tables:';
   $orm->tables
       ->map('name')
       ->say
       ->completed
  })->get;

=cut

use List::Util qw(sum0);

use Database::Async::ORM::Table;
use Database::Async::ORM::Type;
use Database::Async::ORM::Field;
use Database::Async::ORM::Schema;

sub new {
    my $class = shift;
    bless { @_ }, $class
}

sub add_schema {
    my ($self, $schema) = @_;
    push @{$self->{schema}}, $schema;
}

sub schemata {
    shift->{schema}->@*
}

sub schema_by_name {
    my ($self, $name) = @_;
    my ($schema) = grep { $_->name eq $name } $self->schemata or die 'cannot find schema ' . $name . ', have these instead: ' . join(',', map $_->name, $self->schemata);
    return $schema;
}

sub schema_definitions { shift->{schema_definitions} }

=head2 load_from

Loads schema, tables, types and any other available objects from
a source - currently supports the following:

=over 4

=item * hashref

=item * YAML file

=item * directory of YAML files

=back

You can call this multiple times to accumulate objects from various
different sources.

Returns the current L<Database::Async::ORM> instance.

=cut

sub load_from {
    my ($class, $source, $loader) = @_;
    die 'needs a source to load from' unless defined $source;

    $source = $self->read_from($source, $loader) unless ref $source;
    $self->{schema_definitions} = $source;

    my %pending = (type => []);
    for my $schema_name (sort keys $cfg->{schema}->%*) {
        $log->debugf('%s', $schema_name);
        my $schema_details = $cfg->{schema}{$schema_name};

        my $schema = Database::Async::ORM::Schema->new(
            defined_in => $schema_details->{defined_in},
            name       => $schema_name
        );
        $orm->add_schema($schema);
        push @pending, $schema;

        for my $type_name (sort keys $schema_details->{types}->%*) {
            my $type_details = $schema_details->{types}{$type_name};
            push $pending{type}->@*, {
                schema  => $schema,
                name    => $type_name,
                details => $type_details,
            }
        }

        for my $table_name (sort keys $schema_details->{tables}->%*) {
            my $table_details = $schema_details->{tables}{$table_name};
            for($table_details->{fields}->@*) {
                $_->{nullable} = 1 unless exists $_->{nullable} 
            }
            push $pending{table}->@*, {
                schema  => $schema,
                name    => $table_name,
                details => $table_details,
            }
        }
    }

    my $found = 0;
    my @missing;
    while(sum0 map { 0 + @$_ } values %pending) {
        @missing = ();
        $log->tracef('Have %d pending types to check', 0 + $pending{type}->@*);
        for my $item (splice $pending{type}->@*) {
            my $type_name = $item->{name};
            my $type_details = $item->{details};
            my $schema = $item->{schema};
            try {
                $log->debugf('Add type %s as %s', $type_name, $type_details);
                my @fields;
                for my $field_details ($type_details->{fields}->@*) {
                    my $type = $field_details->{type};
                    if(ref $type) {
                        $type = $orm->schema_by_name(
                            $type->{schema}
                        )->type_by_name(
                            $type->{name}
                        )
                    } else {
                        $type = $schema->type_by_name($type);
                    }
                    push @fields, Database::Async::ORM::Field->new(
                        type => $type,
                        name => $field_details->{name},
                        nullable => 1,
                    )
                }
                my $type = Database::Async::ORM::Type->new(
                    defined_in  => $type_details->{defined_in},
                    name        => $type_name,
                    schema      => $schema,
                    type        => $type_details->{type} // 'enum',
                    description => $type_details->{description},
                    values      => $type_details->{data},
                    (exists $type_details->{is} ? (basis => $type_details->{is}) : ()),
                    fields      => \@fields,
                );
                $schema->add_type($type);
                push @pending, $type;
                ++$found;
            } catch {
                $log->tracef('Failed to apply %s.%s - %s, moved to pending',
                    $schema->name,
                    $type_name,
                    $@
                );
                push @missing, {
                    schema => $schema->name,
                    name   => $type_name,
                    type   => 'type',
                    error  => $@
                };
                push $pending{type}->@*, $item;
            }
        }

        $log->tracef('Have %d pending tables to check', 0 + $pending{table}->@*);

        for my $item (splice $pending{table}->@*) {
            my $table_name = $item->{name};
            my $table_details = $item->{details};
            my $schema = $item->{schema};
            try {
                my $table = $self->populate_table(
                    schema => $schema,
                    details => $table_details,
                    name => $table_name
                );
                push @pending, $table;
                ++$found;
            } catch {
                $log->debugf('Failed to apply %s.%s - %s, moved to pending',
                    $schema->name,
                    $table_name,
                    $@
                );
                push @missing, {
                    schema => $schema->name,
                    name   => $table_name,
                    type   => 'table',
                    error  => $@
                };
                push $pending{table}->@*, $item;
            }
        }
    } continue {
        if(@missing and not $found) {
            $log->error('Currently pending items:');
            s/\v+$// for map $_->{error}, @missing;
            $log->errorf('- %s.%s (%s) - %s', $_->{schema}, $_->{name}, $_->{type}, $_->{error}) for @missing;
            die 'Unable to resolve dependencies, bailing out' 
        }
        $found = 0;
    }
    return Future->done;
}

=head2 METHODS - Internal

These are used by L<Database::Async::ORM> and the precise API details
may change in future.

=cut

=head2 populate_table

Populates a L<Database::Async::ORM::Table> instance.

=cut

sub populate_table {
    my ($self, %args) = @_;
    my $table_name = $args{name};
    my $table_details = $args{details};
    my $schema = $args{schema};
    $log->infof('Add table %s as %s', $table_name, $table_details);
    my $table = Database::Async::ORM::Table->new(
        defined_in  => $table_details->{defined_in},
        name        => $table_name,
        schema      => $schema,
        table       => $table_details->{table} // 'enum',
        description => $table_details->{description},
        values      => $table_details->{data},
    );
    for my $field_details ($table_details->{fields}->@*) {
        my $type = $field_details->{type};
        if(ref $type) {
            $type = $orm->schema_by_name(
                $type->{schema}
            )->type_by_name(
                $type->{name}
            )
        } else {
            $type = $schema->type_by_name($type);
        }
        my $field = Database::Async::ORM::Field->new(
            defined_in => $table_details->{defined_in},
            table      => $table,
            type       => $type,
            %{$field_details}{grep { exists $field_details->{$_} } qw(name description)}
        );
        $log->infof('Add field %s as %s with type %s', $field->name, $field_details, $field->type);
        push $table->{fields}->@*, $field;
    }
    $schema->add_table($table);
    return $table;
}

=head2 read_from

Reads data from a file or recursively from a base path.

=cut

sub read_from {
    my ($class, $source, $loader) = @_;
    die 'needs a source to load from' unless defined $source;

    my $base = path($source);
    die "$source does not exist" unless $base->exists;

    $loader //= sub {
        my ($path) = @_;
        if($path->basename eq $path->basename(qw(.yaml .yml))) {
            require YAML::XS;
            return YAML::XS::LoadFile("$path")
        } elsif($path->basename eq $path->basename(qw(.yaml .yml))) {
            require JSON::MaybeXS;
            return JSON::MaybeXS->new->decode($path->slurp_utf8);
        } else {
            die 'Unknown file type for ' . $path;
        }
    };

    # return $loader->($base) unless $base->is_dir;

    my $cfg = $self->schema_definitions // {};

    # Merge in the data from all files recursively.
    # For example, schema/personal/tables/address.yml would populate
    # the {schema}->{personal}->{tables}->{address} element.
    $base->visit(sub {
        my $file = $_;
        unless($_->is_file) {
            $log->tracef('Skipping %s since it is not a file', "$_");
            return;
        }

        # Strip off the base prefix so that we have something that matches our
        # desired hash data path
        my $relative = substr $_, 1 + length($base->stringify);

        # Also drop any file extensions
        $relative =~ s{\.[^.]+$}{};

        # We now want to recurse into our configuration data stucture to the appropriate level.
        my $target = do {
            my $target = $cfg;
            my (@path) = split qr{/}, $relative;
            $target = ($target->{$_} //= {}) for @path;
            $target
        };

        # So at this point, $target indicates where we should load data into our structure.
        # For now, we're blindly overwriting, but ideally we should merge the data structure
        # recursively with the elements in the file.
        $log->debugf('Pulling in configuration from %s', join '.', split qr{/}, $relative);
        my $file_data = $loader->($_);
        if(ref($file_data) eq 'ARRAY') {
            push @$target, @$file_data;
        } elsif(ref($file_data) eq 'HASH') {
            $target->{defined_in} = substr $file, 1 + length($base->stringify);
            @{$target}{keys %$file_data} = values %$file_data;
        } else {
            die 'Unknown data type in file ' . $_ . ' - ' . ref($file_data) . " (actual value $file_data)";
        }
    }, {
        recurse => 1,
        follow_symlinks => 1
    });
}

1;

__END__

=head1 SEE ALSO

=head1 AUTHOR

Tom Molesworth C<< <TEAM@cpan.org> >>

=head1 LICENSE

Copyright Tom Molesworth 2018-2019. Licensed under the same terms as Perl itself.

