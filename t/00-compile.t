use 5.006;
use strict;
use warnings;

# this test was generated with Dist::Zilla::Plugin::Test::Compile 2.058

use Test::More;

plan tests => 20 + ($ENV{AUTHOR_TESTING} ? 1 : 0);

my @module_files = (
    'Database/Async.pm',
    'Database/Async/Backoff.pm',
    'Database/Async/Backoff/Exponential.pm',
    'Database/Async/Backoff/None.pm',
    'Database/Async/DB.pm',
    'Database/Async/Engine.pm',
    'Database/Async/Engine/Empty.pm',
    'Database/Async/ORM.pm',
    'Database/Async/ORM/Constraint.pm',
    'Database/Async/ORM/Extension.pm',
    'Database/Async/ORM/Field.pm',
    'Database/Async/ORM/Schema.pm',
    'Database/Async/ORM/Table.pm',
    'Database/Async/ORM/Type.pm',
    'Database/Async/Pool.pm',
    'Database/Async/Query.pm',
    'Database/Async/Row.pm',
    'Database/Async/StatementHandle.pm',
    'Database/Async/Test.pm',
    'Database/Async/Transaction.pm'
);



# no fake home requested

my @switches = (
    -d 'blib' ? '-Mblib' : '-Ilib',
);

use File::Spec;
use IPC::Open3;
use IO::Handle;

open my $stdin, '<', File::Spec->devnull or die "can't open devnull: $!";

my @warnings;
for my $lib (@module_files)
{
    # see L<perlfaq8/How can I capture STDERR from an external command?>
    my $stderr = IO::Handle->new;

    diag('Running: ', join(', ', map { my $str = $_; $str =~ s/'/\\'/g; q{'} . $str . q{'} }
            $^X, @switches, '-e', "require q[$lib]"))
        if $ENV{PERL_COMPILE_TEST_DEBUG};

    my $pid = open3($stdin, '>&STDERR', $stderr, $^X, @switches, '-e', "require q[$lib]");
    binmode $stderr, ':crlf' if $^O eq 'MSWin32';
    my @_warnings = <$stderr>;
    waitpid($pid, 0);
    is($?, 0, "$lib loaded ok");

    shift @_warnings if @_warnings and $_warnings[0] =~ /^Using .*\bblib/
        and not eval { +require blib; blib->VERSION('1.01') };

    if (@_warnings)
    {
        warn @_warnings;
        push @warnings, @_warnings;
    }
}



is(scalar(@warnings), 0, 'no warnings found')
    or diag 'got warnings: ', ( Test::More->can('explain') ? Test::More::explain(\@warnings) : join("\n", '', @warnings) ) if $ENV{AUTHOR_TESTING};


