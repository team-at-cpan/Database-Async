package Database::Async::Row;
use Full::Class qw(:v1);

# VERSION
# AUTHORITY

=head1 NAME

Database::Async::Row - represents a single row response

=head1 DESCRIPTION


=cut

field $data:param:reader = [];
field $index_by_name:param:reader = {};

=head1 METHODS

=cut

=head2 field

=cut

method field ($name) {
    $self->{data}[$self->{index_by_name}{$name} // die 'unknown field ' . $name]->{data}
}

1;

__END__

=head1 AUTHOR

Tom Molesworth C<< <TEAM@cpan.org> >>

=head1 LICENSE

Copyright Tom Molesworth 2011-2024. Licensed under the same terms as Perl itself.

