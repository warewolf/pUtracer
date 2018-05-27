package TubeDatabase;

use strict;
use warnings;

use Exporter qw( import );
use Data::Dumper qw( Dumper );

our @EXPORT = qw( initdb insert_triode insert_pentode @pentode_fields);

use DBI;

our @pentode_fields = qw( type serial ia is ra rs gma gms mua mus dIa_dVs dIs_dVa );

my $dbh = DBI->connect( "dbi:SQLite:dbname=tubes.sq3", "", "" );

sub initdb {

    $dbh->do( "
        CREATE TABLE IF NOT EXISTS pentodes (
          'type' text,
          'serial' integer,
          'ia' real,
          'is' real,
          'ra' real,
          'rs' real,
          'gma' real,
          'gms' real,
          'mua' real,
          'mus' real,
          'dIa_dVs' real,
          'dIs_dVa' real,
          PRIMARY KEY (type,serial) 
        );
        " );

    $dbh->do( "
        CREATE TABLE IF NOT EXISTS pentode_types (
          'type' text,
          'ia' real,
          'is' real,
          'ra' real,
          'gma' real,
          'mua' real,
          PRIMARY KEY (type) 
        );
        " );

    $dbh->do( "
        CREATE TABLE IF NOT EXISTS triodes (
          'type' text,
          'serial' integer,
          'ia' real,
          'is' real,
          'ra' real,
          'rs' real,
          'gma' real,
          'gms' real,
          'mua' real,
          'mus' real,
          PRIMARY KEY (type,serial) 
        );
        " );

    $dbh->do( "
        CREATE TABLE IF NOT EXISTS triode_types (
          'type' text,
          'ia' real,
          'is' real,
          'ra' real,
          'gma' real,
          'mua' real,
          PRIMARY KEY (type) 
        );
        " );
}

sub insert_pentode {
    my $results = shift;
    
    my @fields = qw( type serial ia is ra rs gma gms mua mus dIa_dVs dIs_dVa );
    my @values;
    
    foreach my $field (@fields) {
        push @values, $results->{$field};    
    }

    my $sth = $dbh->prepare(
        "REPLACE INTO pentodes ('type','serial','ia','is','ra','rs','gma','gms','mua','mus','dIa_dVs','dIs_dVa')
                         VALUES (?,?,?,?,?,?,?,?,?,?,?,?);"
    );
    $sth->execute( @values );
}


