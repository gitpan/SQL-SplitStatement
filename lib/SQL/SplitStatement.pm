package SQL::SplitStatement;

use Moose;

our $VERSION = '0.05003';
$VERSION = eval $VERSION;

use SQL::Tokenizer qw(tokenize_sql);
use List::MoreUtils qw(firstval each_array);

use constant {
    SEMICOLON     => ';',
    FORWARD_SLASH => '/',
    PLACEHOLDER   => '?'
};

my $transaction_re = qr[^(?:
    ;
    |/
    |WORK
    |TRAN
    |TRANSACTION
    |ISOLATION
    |READ
)$]xi;
my $procedural_END_re = qr/^(?:IF|LOOP)$/i;
my $terminator_re     = qr[;|/|;\s+/];
my $begin_comment_re  = qr/^(?:--|\/\*)/;
my $DECLARE_re        = qr/^(?:DECLARE|PROCEDURE|FUNCTION)$/i;
my $PACKAGE_re        = qr/^PACKAGE$/i;
my $BEGIN_re          = qr/^BEGIN$/i;
my $END_re            = qr/^END$/i;

my $CREATE_ALTER_re            = qr/^(?:CREATE|ALTER)$/i;
my $OR_REPLACE_re              = qr/^(?:OR|REPLACE)$/i;
my $OR_REPLACE_PACKAGE_BODY_re = qr/^(?:OR|REPLACE|PACKAGE|BODY)$/i;

my $BODY_re = qr/^BODY$/i;

has [ qw(
    keep_terminator
    keep_extra_spaces
    keep_empty_statements
    keep_comments
)] => (
    is      => 'rw',
    isa     => 'Bool',
    default => undef
);

# TODO: DEPRECATED, to remove!
has 'keep_semicolon' => (
    is      => 'rw',
    isa     => 'Bool',
    default => undef,
    trigger => \&_set_keep_terminator
);

sub _set_keep_terminator {
    my ($self, $value) = @_;
    $self->keep_terminator($value)
}

sub split {
    my ($self, $code) = @_;
    my ( $statements, undef ) = $self->split_with_placeholders($code);
    return @$statements
}

sub split_with_placeholders {
    my ($self, $code) = @_;
    
    my $statement = '';
    my @statements = ();
    my $inside_block = 0;
    my $inside_create_alter = 0;
    my $inside_declare = 0;
    my $inside_package = 0;
    my $package_name = '';
    my $statement_placeholders = 0;
    my @placeholders = ();
    
    my @tokens = tokenize_sql($code);
    
    while ( defined( my $token = shift @tokens ) ) {
        $statement .= $token
            unless $self->_is_comment($token) && ! $self->keep_comments;
        
        if ( $self->_is_BEGIN_of_block($token, \@tokens) ) {
            $inside_block++;
            $inside_declare = 0
        }
        elsif ( $token =~ $CREATE_ALTER_re ) {
            $inside_create_alter = 1;
            
            my $next_token
                = $self->_get_next_significant_token(\@tokens, $OR_REPLACE_re);
            
            if ( $next_token =~ $PACKAGE_re ) {
                $inside_package = 1;
                $package_name = $self->_get_package_name(\@tokens)
            }
        
        }
        elsif ( $token =~ $DECLARE_re ) {
            $inside_declare = 1
        }
        elsif ( my $name = $self->_is_END_of_block($token, \@tokens) ) {
            $inside_block-- if $inside_block;
            if ($name eq $package_name) {
                $inside_package = 0;
                $package_name = ''
            }
        }
        elsif ( $token eq PLACEHOLDER ) {
            $statement_placeholders++
        }
        elsif ( $self->_is_terminator($token, \@tokens) ) {
            $inside_create_alter = 0
        }
        
        next if ! $self->_is_terminator($token, \@tokens)
            || $inside_block || $inside_declare || $inside_package;
        
        push @statements, $statement;
        push @placeholders, $statement_placeholders;
        $statement = '';
        $statement_placeholders = 0;
    }
    push @statements, $statement;
    push @placeholders, $statement_placeholders;
    
    my ( @filtered_statements, @filtered_placeholders );
    
    if ( $self->keep_empty_statements ) {
        @filtered_statements   = @statements;
        @filtered_placeholders = @placeholders
    } else {
        my $sp = each_array( @statements, @placeholders );
        while ( my ($statement, $placeholder_num ) = $sp->() ) {
            unless ( $statement =~ /^\s*$terminator_re?\s*$/ ) {
                push @filtered_statements  , $statement;
                push @filtered_placeholders, $placeholder_num
            }
        }
    }
    
    unless ( $self->keep_terminator ) {
        s/$terminator_re$// foreach @filtered_statements
    }
    
    unless ( $self->keep_extra_spaces ) {
        s/^\s+|\s+$//g foreach @filtered_statements
    }
    
    return ( \@filtered_statements, \@filtered_placeholders )
}

sub _is_comment {
    my ($self, $token) = @_;
    return $token =~ $begin_comment_re
}

sub _is_BEGIN_of_block {
    my ($self, $token, $tokens) = @_;
    return 
        $token =~ $BEGIN_re
        && $self->_get_next_significant_token($tokens) !~ $transaction_re
}

sub _is_END_of_block {
    my ($self, $token, $tokens) = @_;
    my $next_token = $self->_get_next_significant_token($tokens);
    
    # Return possible package name
    return $next_token || 1
        if $token =~ $END_re && (
            ! defined($next_token)
            || $next_token !~ $procedural_END_re
        );
    
    return
}

sub _get_package_name {
    my ($self, $tokens) = @_;
    return $self->_get_next_significant_token(
        $tokens, $OR_REPLACE_PACKAGE_BODY_re
    )
}

sub _is_terminator {
    my ($self, $token, $tokens) = @_;
    
    return   if $token ne FORWARD_SLASH && $token ne SEMICOLON;
    return 1 if $token eq FORWARD_SLASH;
    
    # $token eq SEMICOLON
    my $next_token = $self->_get_next_significant_token($tokens);
    return 1 if ! defined($next_token) || $next_token ne FORWARD_SLASH;
    # $next_token eq FORWARD_SLASH
    return
}

sub _get_next_significant_token {
    my ($self, $tokens, $skiptoken_re) = @_;
    return $skiptoken_re
        ? firstval {
            /\S/ && ! $self->_is_comment($_) && ! /$skiptoken_re/
        } @$tokens
        : firstval {
            /\S/ && ! $self->_is_comment($_)
        } @$tokens
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

SQL::SplitStatement - Split any SQL code into atomic statements

=head1 VERSION

Version 0.05003

=head1 SYNOPSIS

    my $sql_code = <<'SQL';
    CREATE TABLE parent(a, b, c   , d    );
    CREATE TABLE child (x, y, "w;", "z;z");
    /* C-style comment; */
    CREATE TRIGGER "check;delete;parent;" BEFORE DELETE ON parent WHEN
        EXISTS (SELECT 1 FROM child WHERE old.a = x AND old.b = y)
    BEGIN
        SELECT RAISE(ABORT, 'constraint failed;'); -- Inlined SQL comment
    END;
    -- Standalone SQL; comment; with semicolons;
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

This is a simple module which tries to split any SQL code (even when containing
procedural extensions) into the atomic statements it is composed of.

The logic used to split the SQL code is more sophisticated than a raw C<split>
on the I<statement terminator token>, so that SQL::SplitStatement is able to
correctly handle the presence of said token inside identifiers, values,
comments, C<BEGIN ... END> blocks (even nested) and procedural code, as
(partially) exemplified in the synopsis above.

Consider however that this is by no means a validating parser: it requests its
input to be syntactically valid SQL, otherwise it can return unusable statements
(that shouldn't be a problem though, as the original SQL code would have been
unusable anyway).

If the given SQL code is I<valid>, it is guaranteed however that it will be
split correctly (otherwise it is a bug, that will be fixed, once reported).
For the exact definition of I<valid code>, please see the L</LIMITATIONS>
section below.

If your atomic statements are to be fed to a DBMS, you are encouraged to use
L<DBIx::MultiStatementDo> instead, which uses this module and also (optionally)
offers automatic transactions support, so that you'll have the I<all-or-nothing>
behavior you would probably want.

=head1 METHODS

=head2 C<new>

=over 4

=item * C<< SQL::SplitStatement->new( \%options ) >>

=back

It creates and returns a new SQL::SplitStatement object. It accepts its options
either as a hash or a hashref.

C<new> takes the following Boolean options, which all default to false.

=over 4

=item * C<keep_semicolon>

B<WARNING!> This option (and its getter/set method) is now deprecated and it
will be removed in some future version. It has been renamed to:
C<keep_terminator>, so please use that instead. Currently any value assigned
to C<keep_semicolon> is assigned to C<keep_terminator>.

=item * C<keep_terminator>

A Boolean option which causes, when set to a false value (which is the default),
the trailing terminator token to be discarded in the returned atomic statements.
When set to a true value, the terminators are kept instead.

If your statements are to be fed to a DBMS, you are advised to keep this option
to its default (false) value, since some drivers/DBMS don't want the
terminator to be present at the end of the (single) statement.

The strings currently recognized as terminator tokens are:

=over 4

=item * C<;> (the I<semicolon> character)

=item * C</> (the I<forward-slash> character)

=item * a semicolon followed by a forward-slash on its own line

This latter string is treated as a single token (it is used to terminate
PL/SQL procedures).

=back

(Note that the last, possibly empty, statement of a given SQL text, never has a
trailing terminator. See below for an example.)

=item * C<keep_extra_spaces>

A Boolean option which causes, when set to a false value (which is the default),
the spaces (C<\s>) around the statements to be trimmed.
When set to a true value, these spaces are kept instead.

When C<keep_terminator> is set to false as well, the terminator is discarded
first (regardless of the spaces around it) and the trailing spaces are trimmed
then. This ensures that if C<keep_extra_spaces> is set to false, the returned
statements will never have trailing (nor leading) spaces, regardless of the
C<keep_terminator> value.

=item * C<keep_comments>

A Boolean option which causes, when set to a false value (which is the default),
the comments to be discarded in the returned statements. When set to a true
value, they are kept with the statements instead.

Both SQL and multi-line C-style comments are recognized.

When kept, each comment is returned in the same string with the atomic statement
it belongs to. A comment belongs to a statement if it appears, in the original
SQL code, before the end of that statement and after the terminator of the
previous statement (if it exists), as shown in this meta-SQL snippet:

    /* This comment
    will be returned
    with statement1 */
    <statement1>; -- This will go with statement2
                  -- (note the semicolon which closes statement1)

    <statement2>
    -- This with statement2 as well

=item * C<keep_empty_statements>

A Boolean option which causes, when set to a false value (which is the default),
the empty statements to be discarded. When set to a true value, the empty
statements are returned instead.

A statement is considered empty when it contains no character other than the
terminator and space characters (C<\s>).

A statement composed solely of comments is not recognized as empty and may
therefore be returned even when C<keep_empty_statements> is false. To avoid
this, it is sufficient to leave C<keep_comments> to false as well.

Note instead that an empty statement is recognized as such regardless of the
value of the options C<keep_terminator> and C<keep_extra_spaces>.

=back

These options are basically to be kept to their default (false) values,
especially if the atomic statements are to be given to a DBMS.

They are intended mainly for I<cosmetic> reasons, or if you want to count by how
many atomic statements, including the empty ones, your original SQL code was
composed of.

Another situation where they are useful (in the general case necessary, really),
is when you want to retain the ability to verbatim rebuild the original SQL
string from the returned statements:

    my $verbatim_splitter = SQL::SplitStatement->new(
        keep_terminator       => 1,
        keep_extra_spaces     => 1,
        keep_comments         => 1,
        keep_empty_statements => 1
    );

    my @verbatim_statements = $verbatim_splitter->split($sql_string);

    $sql_string eq join '', @verbatim_statements; # Always true, given the constructor above.

Other than this, again, you are highly recommended to stick with the defaults.

=head2 C<split>

=over 4

=item * C<< $sql_splitter->split( $sql_string ) >>

=back

This is the method which actually splits the SQL code into its atomic
components.

It returns a list containing the atomic statements, in the same order they
appear in the original SQL code. The atomic statements are returned according to
the options explained above.

Note that, as mentioned above, an SQL string which terminates with a terminator
token (for example a semicolon), contains a trailing empty statement: this is
correct and it is treated accordingly (if C<keep_empty_statements> is set to a
true value):

    my $sql_splitter = SQL::SplitStatement->new(
        keep_empty_statements => 1
    );

    my @statements = $sql_splitter->split( 'SELECT 1;' );

    print 'The SQL code contains ' . scalar(@statements) . ' statements.';
    # The SQL code contains 2 statements.

=head2 C<split_with_placeholders>

=over 4

=item * C<< $sql_splitter->split_with_placeholders( $sql_string ) >>

=back

It works exactly as the C<split> method explained above, except that it returns
also a list of integers, each of which is the number of the (I<unnamed>)
I<placeholders> (aka I<parameter markers> - represented by the C<?> character)
contained in the corresponding atomic statements.

Its return value is a list of two elements: the first one is a reference to the
list of the atomic statements (exactly as returned by the C<split> method), and
the second is a reference to the list of the numbers of placeholders as
explained above.

Here is an example:

    # 4 statements (valid SQLite SQL)
    my $sql_code = <<'SQL';
    CREATE TABLE state (id, name);
    INSERT INTO  state (id, name) VALUES (?, ?);
    CREATE TABLE city  (id, name, state_id);
    INSERT INTO  city  (id, name, state_id) VALUES (?, ?, ?)
    SQL

    my $splitter = SQL::SplitStatement->new;

    my ( $statements, $placeholders )
        = $splitter->split_with_placeholders( $sql_code );

    # $placeholders is [0, 2, 0, 3]

where the returned C<$placeholders> list(ref) is to be read as follows:
the first statement has 0 placeholders, the second 2, the third 0, the fourth 3.

=head2 C<keep_terminator>

=over 4

=item * C<< $sql_splitter->keep_terminator >>

=item * C<< $sql_splitter->keep_terminator( $boolean ) >>

Getter/setter method for the C<keep_terminator> option explained above.

=back

=head2 C<keep_extra_spaces>

=over 4

=item * C<< $sql_splitter->keep_extra_spaces >>

=item * C<< $sql_splitter->keep_extra_spaces( $boolean ) >>

Getter/setter method for the C<keep_extra_spaces> option explained above.

=back

=head2 C<keep_comments>

=over 4

=item * C<< $sql_splitter->keep_comments >>

=item * C<< $sql_splitter->keep_comments( $boolean ) >>

Getter/setter method for the C<keep_comments> option explained above.

=back

=head2 C<keep_empty_statements>

=over 4

=item * C<< $sql_splitter->keep_empty_statements >>

=item * C<< $sql_splitter->keep_empty_statements( $boolean ) >>

Getter/setter method for the C<keep_empty_statements> option explained above.

=back

=head1 LIMITATIONS

To be split correctly, it is not sufficient that the given code is syntactically
valid SQL. It is also required that the keywords
C<BEGIN>, C<DECLARE>, C<FUNCTION> and C<PROCEDURE> (case-insensitive) are not
used as (I<bare>) object identifiers (e.g. table names, field names etc.)
They can however be used, as long as they are quoted, as shown here:

    CREATE TABLE  declare  (  begin  VARCHAR ); -- Wrong, though accepted by some DBMS.
    CREATE TABLE "declare" ( "begin" VARCHAR ); -- Correct!

The only procedural code currently recognized is PL/SQL, that is, blocks of
code which start with a C<DECLARE>, a C<CREATE> or I<anonymous>
C<BEGIN ... END> blocks.

If you need also other procedural languages to be recognized, please let me know
(possibly attaching test cases).

=head1 DEPENDENCIES

SQL::SplitStatement depends on the following modules:

=over 4

=item * L<Moose>

=item * L<List::MoreUtils>

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
