#!/usr/bin/perl

use Test::More;
use Test::Pod::LinkCheck;

# Okay, we test each backend N times
my @backends = qw( CPANPLUS CPAN CPANSQLite );
plan tests => scalar @backends * 3;

foreach my $backend ( @backends ) {
	my $t = Test::Pod::LinkCheck->new( cpan_backend => $backend, verbose => 0 );

	# Query for a valid CPAN module
	my $res = $t->_known_cpan( 'Test::More' );
	if ( defined $res ) {
		is( $res, 1, "Test::More check on $backend" );
	} else {
		TODO: {
			local $TODO = "Not all backends are installed";
			fail( "Test::More check on $backend" );
		}
	}

	# Query for a valid CPAN module ( test the cache )
	$res = $t->_known_cpan( 'Test::More' );
	if ( defined $res ) {
		is( $res, 1, "Test::More check on $backend (cached)" );
	} else {
		TODO: {
			local $TODO = "Not all backends are installed";
			fail( "Test::More check on $backend" );
		}
	}

	# Query for an invalid CPAN module
	$res = $t->_known_cpan( 'Foolicious::Surely::Does::Not::Exist' );
	if ( defined $res ) {
		is( $res, 0, "Foolicious check on $backend" );
	} else {
		TODO: {
			local $TODO = "Not all backends are installed";
			fail( "Foolicious check on $backend" );
		}
	}
}
