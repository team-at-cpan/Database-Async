package Database::Async;
# ABSTRACT: database interface for use with IO::Async
use Full::Class qw(:v1), extends => 'IO::AsyncX::Notifier';

our $VERSION = '0.019';

=head1 NAME

Database::Async - provides a database abstraction layer for L<IO::Async>

=head1 SYNOPSIS

 use Database::Async;
 use Future::AsyncAwait;
 # Just looking up one thing?
 my ($id) = await $db->query(
  q{select id from some_table where name = ?},
  bind => ['some name']
 )->single;

 # Simple query
 $db->query(q{select id, some_data from some_table})
    ->row_hashrefs
    ->each(sub {
        printf "ID %d, data %s\n", $_->{id}, $_->{some_data};
    })
    # If you want to complete the full query, don't forget to call
    # ->get or ->retain here!
    ->retain;

 # Transactions: this returns a Future, so if you want to wait for it to complete,
 # call `->get` (throws an exception if something goes wrong)
 # or `->await` (just waits for it to succeed or fail, but ignores
 # the result).
 await $db->transaction(async sub {
  my ($tx) = @_;
 })->commit;

 # Alternatively, call ->txn and use the resulting object like a database handle
 my $txn = $db->txn;
 await $txn->query(q{update something set key = 'value'});
 if(rand > 0.5) {
  await $txn->commit;
 } else {
  await $txn->rollback;
 }

=head1 DESCRIPTION

Database support for L<IO::Async>. This is the base API, see L<Database::Async::Engine>
and subclasses for specific database functionality.

L<DBI> provides a basic API for interacting with a database, but this is
very low level and uses a synchronous design. See L<DBIx::Async> if you're
familiar with L<DBI> and want an interface that follows it more closely.

Typically a database only allows a single query to run at a time.
Other queries will be queued.

=head2 Connection pool

Use the C<pool> parameter to set up a pool of connections to provide better parallelism:

    my $dbh = Database::Async->new(
        uri  => 'postgresql://write@maindb/dbname?sslmode=require',
        pool => {
            max => 4,
        },
    );

Queries and transactions will then automatically be distributed
among these connections. Note that:

=over 4

=item * all queries within a transaction will be made on the same connection

=item * outside a transaction, queries will be started in order on the next
available connection

=back

With a single connection, you could expect:

    Future->needs_all(
     $dbh->do(q{insert into x ...}),
     $dbh->do(q{select from x ...})
    );

to insert the rows first, then return them in the C<select> call. B<With a pool of connections, that's not guaranteed>.

=head3 Pool configuration

The following parameters are currently accepted for defining the pool:

=over 4

=item * C<min> - minimum number of total connections to maintain, defaults to 0

=item * C<max> - maximum permitted active connections, default is 1

=item * C<ordering> - how to iterate through the available URIs, options include
C<random> and C<serial> (default, round-robin behaviour).

=item * C<backoff> - algorithm for managing connection timeouts or failures. The default
is an exponential backoff with 10ms initial delay, 30s maximum, resetting on successful
connection.

=back

See L<Database::Async::Pool> for more details.

=head2 DBI

The interface is not the same as L<DBI>, but here are some approximate equivalents for
common patterns:

=head3 selectall_hashref

In L<DBI>:

 print $_->{id} . "\n" for
  $dbh->selectall_hashref(
   q{select * from something where id = ?},
   undef,
   $id
  )->@*;

In L<Database::Async>:

 print $_->{id} . "\n" for (
  await $db->query(
   q{select * from something where id = ?}, $id
  )->row_hashrefs
   ->as_arrayref
 )->@*;

In L<DBI>:

 my $sth = $dbh->prepare(q{select * from something where id = ?});
 for my $id (1, 2, 3) {
  $sth->bind(0, $id, 'bigint');
  $sth->execute;
  while(my $row = $sth->fetchrow_hashref) {
   print $row->{name} . "\n";
  }
 }

In L<Database::Async>:

 my $sth = $db->prepare(q{select * from something where id = ?});
 await Future::Utils::fmap_void(async sub ($id) {
  await $sth->bind(0, $id, 'bigint');
  await $sth->execute;
  await $sth->row_hashrefs
     ->each(sub {
      print $_->{name} . "\n";
     })->completed;
 } foreach => [1, 2, 3 ], concurrent => 3);

=cut

use URI;
use URI::db;
use Module::Load ();

use Database::Async::Engine;
use Database::Async::Pool;
use Database::Async::Query;
use Database::Async::StatementHandle;
use Database::Async::Transaction;

field $encoding : reader;
field $ryu;
field $type:param = undef;
field $uri:param:reader = undef;
field $pool = undef;
field $pool_args:param = [];
field $transactions = [];
field $engine_parameters = +{};
field $notification_source = undef;

=head1 METHODS

=cut

=head2 transaction

Resolves to a L<Future> which will yield a L<Database::Async::Transaction>
instance once ready.

=cut

async method transaction (@args) {
    Scalar::Util::weaken(
        $transactions->[$transactions->@*] =
            my $txn = Database::Async::Transaction->new(
                database => $self,
                @args
            )
    );
    await $txn->begin;
    return $txn;
}

=head2 txn

Executes code within a transaction. This is meant as a shorter form of
the common idiom

 $db->transaction
    ->then(sub {
     my ($txn) = @_;
     Future->call($code)
      ->then(sub {
       $txn->commit
      })->on_fail(sub {
       $txn->rollback
      });
    })

The code must return a L<Future>, and the transaction will only be committed
if that L<Future> resolves cleanly.

Returns a L<Future> which resolves once the transaction is committed.

=cut

async method txn ($code, @args) {
    my $txn = await $self->transaction;
    try {
        my @data = await Future->call(
            $code => ($txn, @args)
        );
        await $txn->commit;
        return @data;
    } catch {
        my $exception = $@;
        try {
            await $txn->rollback;
        } catch {
            $log->warnf("exception %s in rollback", $@);
        }
        die $exception;
    }
}

=head1 METHODS - Internal

You're welcome to call these, but they're mostly intended
for internal usage, and the API B<may> change in future versions.

=cut

=head2 uri

Returns the configured L<URI> for populating database instances.

=cut

=head2 pool

Returns the L<Database::Async::Pool> instance.

=cut

method pool {
    unless($pool) {
        $self->add_child(
            $pool = Database::Async::Pool->new(
                $self->pool_args
            )
        );
    }
    return $pool;
}

=head2 pool_args

Returns a list of standard pool constructor arguments.

=cut

method pool_args {
    return (
        request_engine_handler => $self->curry::weak::request_engine,
        uri            => $self->uri,
        $pool_args->@*,
    );
}

=head2 configure

Applies configuration, see L<IO::Async::Notifier> for details.

Supports the following named parameters:

=over 4

=item * C<uri> - the endpoint to use when connecting a new engine instance

=item * C<engine> - the parameters to pass when instantiating a new L<Database::Async::Engine>

=item * C<pool> - parameters for setting up the pool, or a L<Database::Async::Pool> instance

=item * C<encoding> - default encoding to apply to parameters, queries and results, defaults to C<binary>

=back

=cut

my %encoding_map = (
    'utf8'    => 'UTF-8',
    'utf-8'   => 'UTF-8',
    'UTF8'    => 'UTF-8',
    'unicode' => 'UTF-8',
);

method configure (
    %args
) {
    if(my $encoding = delete $args{encoding}) {
        $args{encoding} = $encoding_map{$encoding} // $encoding;
    }

    if(my $uri = delete $args{uri}) {
        # This could be any type of object. We make
        # the assumption here that it safely serialises
        # to a standard URI. Some of the database
        # engines provide such a standard (e.g. PostgreSQL).
        # Others may not...
        $args{uri} = URI->new("$uri");
    }
    if(exists $args{engine}) {
        $args{engine_parameters} = delete $args{engine};
    }
    if(my $pool = delete $args{pool}) {
        if(blessed $pool) {
            $args{pool} = $pool;
        } else {
            $args{pool_args} = [ $pool->%* ];
        }
    }
    $self->next::method(%args);
}

=head2 ryu

A L<Ryu::Async> instance, used for requesting sources, sinks and timers.

=cut

method ryu {
    $ryu //= do {
        $self->add_child(
            my $ryu = Ryu::Async->new
        );
        $ryu
    }
}

=head2 new_source

Instantiates a new L<Ryu::Source>.

=cut

method new_source { $self->ryu->source }

=head2 new_sink

Instantiates a new L<Ryu::Sink>.

=cut

method new_sink { $self->ryu->sink }

=head2 new_future

Instantiates a new L<Future>.

=cut

method new_future { $self->loop->new_future }

=head1 METHODS - Internal, engine-related

=cut

=head2 request_engine

Attempts to instantiate and connect to a new L<Database::Async::Engine>
subclass. Returns a L<Future> which should resolve to a new
L<Database::Async::Engine> instance when ready to use.

=cut

async method request_engine {
    $log->tracef('Requesting new engine');
    my $engine = $self->engine_instance;
    $log->tracef('Connecting');
    return await $engine->connect;
}

=head2 engine_instance

Loads the appropriate engine class and attaches to the loop.

=cut

method engine_instance {
    die 'unknown database type ' . $type
        unless my $engine_class = $Database::Async::Engine::ENGINE_MAP{$type};
    Module::Load::load($engine_class) unless $engine_class->can('new');
    $log->tracef('Instantiating new %s', $engine_class);
    my %param = (
        $engine_parameters->%*,
        (defined($uri) ? (uri => $uri) : ()),
        db => $self,
    );

    # Only recent engine versions support this parameter
    if($encoding) {
        if($engine_class->can('encoding')) {
            $param{encoding} = $self->encoding;
        } else {
            # If we're given this parameter, let's not ignore it silently
            die 'Database engine ' . $engine_class . ' does not support encoding parameter, try upgrading that module from CPAN or remove the encoding configuration in Database::Async';
        }
    }

    $self->add_child(
        my $engine = $engine_class->new(%param)
    );
    warn "invalid engine? $engine\n" unless ref($engine);
    $engine;
}

=head2 engine_ready

Called by L<Database::Async::Engine> instances when the engine is
ready for queries.

=cut

method engine_ready ($engine) {
    $self->pool->queue_ready_engine($engine);
}

method engine_disconnected ($engine) {
    $self->pool->unregister_engine($engine);
}

method db { $self }

=head2 queue_query

Assign the given query to the next available engine instance.

=cut

async method queue_query ($query) {
    $log->tracef('Queuing query %s', $query);
    my $f = $self->pool->next_engine;
    CANCEL { $f->cancel; return undef }
    my $engine = await $f;
    $log->tracef('Query %s about to run on %s', $query, $engine);
    my $q = $engine->handle_query($query);
    CANCEL { $q->cancel; return undef }
    return await $q;
}

method diagnostics { }

method notification ($engine, $channel, $data) {
    $log->tracef('Database notifies us via %s of %s', $channel, $data);
    $self->notification_source($channel)->emit($data);
}

method notification_source ($name) {
    $notification_source->{$name} //= $self->new_source;
}

method _remove_from_loop ($loop) {
    if($ryu) {
        $self->remove_child($ryu);
        undef $ryu;
    }
    if($pool) {
        $self->remove_child($pool);
        undef $pool;
    }
    return $self->next::method($loop);
}

1;

__END__

=head1 SEE ALSO

There's a range of options for interacting with databases - at a low level:

=over 4

=item * L<DBIx::Async> - runs L<DBI> in subprocesses, very inefficient but tries to
make all the methods behave a bit like DBI but deferring results via L<Future>s.

=item * L<DBI> - synchronous database access

=item * L<Mojo::Pg> - attaches a L<DBD::Pg> handle to an event loop

=item * L<Mojo::mysql> - apparently has the ability to make MySQL "fun", an intriguing
prospect indeed

=back

and at higher levels, L<DBIx::Class> or one of the many other ORMs might be
worth a look. Nearly all of those will use L<DBI> in some form or other.

Several years ago I put together a list, the options have doubtless multiplied
since then:

=head2 Asynchronous ORMs

The list here is sadly lacking:

=over 4

=item * L<Async::ORM|https://github.com/vti/async-orm> - asynchronous ORM, see also article in L<http://showmetheco.de/articles/2010/1/mojolicious-async-orm-and-dbslayer.html>

=back

=head2 Synchronous ORMs

If you're happy for the database to tie up your process for an indefinite amount of time, you're in
luck - there's a nice long list of modules to choose from here:

=over 4

=item * L<DBIx::Class> - one of the more popular choices

=item * L<Rose::DB::Object> - written for speed, appears to cover most of the usual requirements, personally
I found the API less intuitive than other options but it appears to be widely deployed

=item * L<Fey::ORM> - "newer" than the other options, also appears to be reasonably flexible

=item * L<DBIx::DataModel> - UML-based Object-Relational Mapping (ORM) framework

=item * L<Alzabo> - another ORM which includes features such as GUI schema editing and SQL diff

=item * L<Class::DBI> - generally considered to be superceded by L<DBIx::Class>, which provides a compatibility
layer for existing applications

=item * L<Class::DBI::Lite> - like L<Class::DBI> but lighter, presumably

=item * L<ORMesque> - lightweight class-based ORM using L<SQL::Abstract>

=item * L<Oryx> - Object persistence framework, meta-model based with support for both DBM and regular RDBMS
backends, uses tied hashes and arrays

=item * L<Tangram> - An object persistence layer

=item * L<KiokuDB> - described as an "Object Graph storage engine" rather than an ORM

=item * L<DBIx::DataModel> - ORM using UML definitions

=item * L<Jifty::DBI> - another ORM

=item * L<ORLite> - minimal SQLite-based ORM

=item * L<Ormlette> - object persistence, "heavily influenced by Adam Kennedy's L<ORLite>". "light and fluffy", apparently!

=item * L<ObjectDB> - another lightweight ORM, currently has only L<DBI> as a dependency

=item * L<ORM> - looks like it has support for MySQL, PostgreSQL and SQLite

=item * L<fytwORM> - described as a "bare minimum ORM used for prototyping / proof of concepts"

=item * L<DBR> - Database Repository ORM

=item * L<SweetPea::Application::Orm> - specific to the L<SweetPea> web framework

=item * L<Jorge> - ORM Made simple

=item * L<Persistence::ORM> - looks like a combination between persistent Perl objects and standard ORM

=item * L<Teng> - lightweight minimal ORM

=item * L<Class::orMapper> - DBI-based "easy O/R Mapper"

=item * L<UR|https://github.com/genome/UR> - class framework and object/relational mapper (ORM) for Perl

=item * L<DBIx::NinjaORM> - "Flexible Perl ORM for easy transitions from inline SQL to objects"

=item * L<DBIx::Oro> - Simple Relational Database Accessor

=item * L<LittleORM> - Moose-based ORM

=item * L<Storm> - another Moose-based ORM

=item * L<DBIx::Mint> - "A mostly class-based ORM for Perl"

=back

=head2 Database interaction

=over 4

=item * L<DBI::Easy> - seems to be a wrapper around L<DBI>

=item * L<AnyData> - interface between L<DBI> and arbitrary data sources such as XML or HTML

=item * L<DBIx::ThinSQL> - helpers for SQL statements

=item * L<DB::Evented> - event-based wrapper for L<DBI>-like behaviour, uses L<AnyEvent::DBI>

=back

=head1 AUTHOR

Tom Molesworth C<< <TEAM@cpan.org> >>

=head1 LICENSE

Copyright Tom Molesworth 2011-2024. Licensed under the same terms as Perl itself.

