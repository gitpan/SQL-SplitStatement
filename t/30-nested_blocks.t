#!perl

use strict;
use warnings;

use DBI;
use SQL::SplitStatement;

use Test::More tests => 2;

# This is artificial, not valid SQL.
# The only important thing is that BEGIN..END blocks are not concatened;
my $sql = <<'SQL';
statement1;
BEGIN
    statement2;
END;
BEGIN
    BegiN
        statement3;
    END;
    bEgIn
        statement3;
        BEGIN
            statement3;
            statement3;
            statement3
        end;
    END;
END;
BEGIN statement4 END
SQL
chop( my $clean_sql = $sql );

my $sql_splitter = SQL::SplitStatement->new;

my @statements = $sql_splitter->split($sql);

cmp_ok (
    scalar(@statements), '==', 4,
    'number of atomic statements'
);

is (
    join( ";\n", @statements ), $clean_sql,
    'SQL code successfully rebuilt'
);
