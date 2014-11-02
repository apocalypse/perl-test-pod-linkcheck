#!/usr/bin/perl

use Test::More;
use Test::Pod::LinkCheck;
my @backends = qw( CPANPLUS CPAN CPANSQLite MetaDB MetaCPAN CPANIDX );
plan tests => scalar @backends * 4;

foreach my $backend ( @backends ) {
	my $t = Test::Pod::LinkCheck->new( cpan_backend => $backend, cpan_backend_auto => 0 );

	TODO: {
		local $TODO = "Maybe '$backend' is not installed/configured properly...";

		# Query for a valid CPAN module
		my $res = $t->_known_cpan( 'Test::More' );
		is( $res, 1, "Test::More check on $backend" );

		# Query for a valid CPAN module ( test the cache )
		$res = $t->_known_cpan( 'Test::More' );
		is( $res, 1, "Test::More check on $backend (cached)" );

		# Query for an invalid CPAN module
		$res = $t->_known_cpan( 'Foolicious::Surely::Does::Not::Exist' );
		is( $res, 0, "Foolicious check on $backend" );

		# Query for an invalid CPAN module ( test the cache )
		$res = $t->_known_cpan( 'Foolicious::Surely::Does::Not::Exist' );
		is( $res, 0, "Foolicious check on $backend (cached)" );
	}
}
