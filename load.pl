#!/usr/bin/perl

use DBI;
my $dbh = DBI->connect("dbi:SQLite:dbname=tubes.sq3","","");

$dbh->do("
CREATE TABLE IF NOT EXISTS tubes (
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
");

my $sth = $dbh->prepare("REPLACE INTO tubes ('type','serial','ia','is','ra','rs','gma','gms','mua','mus') VALUES (?,?,?,?,?,?,?,?,?,?);");

while (<>) {
  chomp;
  next if ($_ =~ m/^Type/);
  $sth->execute(split(m/\t/,$_));
}

