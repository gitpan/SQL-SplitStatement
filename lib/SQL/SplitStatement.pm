package SQL::SplitStatement;

use strict;
use warnings;

our $VERSION = '0.01000';
$VERSION = eval $VERSION;

use SQL::Tokenizer 'tokenize_sql';

use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors( qw/
    keep_semicolon
    keep_extra_spaces
    keep_empty_statements
/);

use constant SEMICOLON => ';';

sub split {
    my ($self, $code) = @_;
    
    my @statements;
    my $statement = '';
    my $inside_block = 0;
    
    foreach ( tokenize_sql($code) ) {
        $statement .= $_;
        if    ( /^BEGIN$/i ) { $inside_block++ }
        elsif ( /^END$/i   ) { $inside_block-- }
        
        next if $_ ne SEMICOLON || $inside_block;
        
        push @statements, $statement;
        $statement = ''
    }
    push @statements, $statement;
    
    return
        map {
            s/;$//         unless $self->keep_semicolon;
            s/^\s+|\s+$//g unless $self->keep_extra_spaces;
            $_
        } $self->keep_empty_statements
            ? @statements
            : grep /[^\s;]/, @statements
}

1;

__END__

=head1 NAME

SQL::SplitStatement - Split any SQL code into atomic statements

=head1 VERSION

Version 0.01000

=head1 SYNOPSIS

    my $sql_code = <<'SQL';
    CREATE TABLE parent(a, b, c   , d    );
    CREATE TABLE child (x, y, "w;", "z;z");
    CREATE TRIGGER "check;delete;parent;" BEFORE DELETE ON parent WHEN
        EXISTS (SELECT 1 FROM child WHERE old.a = x AND old.b = y)
    BEGIN
        SELECT RAISE(ABORT, 'constraint failed;');
    END;
    INSERT INTO parent (a, b, c, d) VALUES ('pippo;', 'pluto;', NULL, NULL);
    SQL
    
    use SQL::SplitStatement;
    
    my $sql_splitter = SQL::SplitStatement->new;
    
    my @statements = $sql_splitter->split($sql_code);
    
    # @statements now is:
    #
    # (
    #     'CREATE TABLE parent(a, b, c   , d    )',
    #     'CREATE TABLE child (x, y, "w;", "z;z")',
    #     'CREATE TRIGGER "check;delete;parent;" BEFORE DELETE ON parent WHEN
    #     EXISTS (SELECT 1 FROM child WHERE old.a = x AND old.b = y)
    # BEGIN
    #     SELECT RAISE(ABORT, \'constraint failed;\');
    # END',
    #     'INSERT INTO parent (a, b, c, d) VALUES (\'pippo;\', \'pluto;\', NULL, NULL)'
    # )

=head1 DESCRIPTION

This is a very simple module which permits to split any (not only DDL) SQL code
into the atomic statements it is composed of.

The logic used to split the SQL code is more sophisticated than a raw
C<split> on the C<;> (semicolon) character,
so that SQL::SplitStatement is able to correctly handle the presence
of the semicolon inside identifiers, values or C<BEGIN..END> blocks
(even nested blocks), as exemplified in the synopsis above.

Consider however that this is by no mean a validating parser: it requests
its input to be syntactically valid SQL, otherwise it can return
unusable statements (that shouldn't be a problem though, as the original SQL
code would have been unusable anyway).

As long as the given SQL code is valid, it is guaranteed however that it will be
split correctly (otherwise it is a bug, that will be corrected once reported).

If your atomic statements are to be fed to a DBMS, you are encouraged to use
L<DBIx::MultiStatementDo> instead, which uses this module and also (optionally)
offer automatic transactions support, so that you'll have the I<all-or-nothing>
behavior you would probably want.

=head1 METHODS

=head2 C<new>

=over 4

=item * C<< SQL::SplitStatement->new( \%options ) >>

=back

It creates and returns a new SQL::SplitStatement object.
It accepts its options as an hashref.

The following options are recognized:

=over 4

=item * C<keep_semicolon>

A boolean option which causes, when set to a false value (which is the default),
the trailing semicolon to be discarded in the returned atomic statements.

When set to a true value, the trailing semicolons are kept instead.

If your statements are to be fed to a DBMS, you are strongly encouraged to
keep this option to its default (false) value, since some drivers/DBMSs
don't accept the semicolon at the end of a statement.

(Note that the last, possibly empty, statement of a given SQL code,
never has a trailing semicolon. See below for an example.)

=item * C<keep_extra_spaces>

A boolean option which causes, when set to a false value (which is the default),
the spaces (C<\s>) around the statements to be trimmed.

When set to a true value, these spaces are kept instead.

When C<keep_semicolon> is set to false as well, the semicolon
is discarded first (regardless of the spaces around it) and the trailing
spaces are trimmed then.
This ensures that if C<keep_extra_spaces> is set to false, the returned
statements will never have trailing (nor leading) spaces, regardless of
the C<keep_semicolon> value.

=item * C<keep_empty_statements>

A boolean option which causes, when set to a false value (which is the default),
the empty statements to be discarded.

When set to a true value, the empty statements are returned instead.

A statement is considered empty when it contains no character other than
the semicolon and space characters (C<\s>).

Note that this option is completely independent to the others, that is,
an empty statement is recognized as such regardless of the values
of the above options C<keep_semicolon> and C<keep_extra_spaces>.

=back

These options are basically to be kept to their default (false) values,
especially if the atomic statements are to be given to a DBMS.

They are intented mainly for I<cosmetic> reasons, or if you want to count
by how many atomic statements, including the empty ones, your original SQL code
was composed of.

Another situation where they are useful (necessary, really), is when you want
to retain the ability to verbatim rebuild the original SQL string from the
returned statements:

    my $verbatim_splitter = SQL::SplitStatement->new({
        keep_semicolon        => 1,
        keep_extra_spaces     => 1,
        keep_empty_statements => 1
    });
    
    my @verbatim_statements = $verbatim_splitter->split($sql);
    
    $sql eq join '', @verbatim_statements; # Always true, given the constructor above.

Other than this, again, you are highly recommended to stick with the defaults.

=head2 C<split>

=over 4

=item * C<< $sql_splitter->split( $sql_string ) >>

=back

This is the method which actually splits the SQL code into its atomic
components.

It returns a list containing the atomic statements, in the same order they
appear in the original SQL code.

Note that, as mentioned above, an SQL string which terminates with a semicolon
contains a trailing empty statement: this is correct and it is treated
accordingly (if C<keep_empty_statements> is set to a true value):

    my $sql_splitter = SQL::SplitStatement->new({
        keep_empty_statements => 1
    });
    
    my @statements = $sql_splitter->split( 'SELECT 1;' );
    
    print 'The SQL code contains ' . scalar(@statements) . ' statements.';
    # The SQL code contains 2 statements.

=head2 C<keep_semicolon>

=over 4

=item * C<< $sql_splitter->keep_semicolon >>

=item * C<< $sql_splitter->keep_semicolon( $boolean ) >>

Getter/setter method for the C<keep_semicolon> option explained above.

=back

=head2 C<keep_extra_spaces>

=over 4

=item * C<< $sql_splitter->keep_extra_spaces >>

=item * C<< $sql_splitter->keep_extra_spaces( $boolean ) >>

Getter/setter method for the C<keep_extra_spaces> option explained above.

=back

=head2 C<keep_empty_statements>

=over 4

=item * C<< $sql_splitter->keep_empty_statements >>

=item * C<< $sql_splitter->keep_empty_statements( $boolean ) >>

Getter/setter method for the C<keep_empty_statements> option explained above.

=back

=head1 DEPENDENCIES

SQL::SplitStatement depends on the following modules:

=over 4

=item * L<Class::Accessor::Fast>

=item * L<SQL::Tokenizer>

=back

=head1 AUTHOR

Emanuele Zeppieri, C<< <emazep@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-sql-SplitStatement at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=SQL-SplitStatement>.
I will be notified, and then you'll automatically be notified of progress
on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc SQL::SplitStatement

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=SQL-SplitStatement>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/SQL-SplitStatement>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/SQL-SplitStatement>

=item * Search CPAN

L<http://search.cpan.org/dist/SQL-SplitStatement/>

=back

=head1 ACKNOWLEDGEMENTS

Igor Sutton for his excellent L<SQL::Tokenizer>, which made writing
this module a joke.

=head1 SEE ALSO

=over 4

=item * L<DBIx::MultiStatementDo>

=back

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Emanuele Zeppieri.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation, or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
