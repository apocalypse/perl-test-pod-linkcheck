#!/usr/bin/perl

use File::Temp qw( tempfile );
use Test::Tester;
use Test::More;
use Test::Pod::LinkCheck;

my %tests = (
	'empty'		=> {
		pod		=> '',
		actual_ok	=> 1,
	},
	'error'		=> {
		pod		=> "=head999",
		actual_ok	=> 0,
	},
	'plain'		=> {
		pod		=> "=head1 NAME\n\nHello from Foobar!",
		actual_ok	=> 1,
	},
	'pass'		=> {
		pod		=> "=head1 NAME\n\nHello from Foobar! Please visit L<Test::More> for more info!",
		actual_ok	=> 1,
	},
	'pass_cpan'		=> {
		pod		=> "=head1 NAME\n\nHello from Foobar! Please visit L<Acme::Drunk> for more info!",
		actual_ok	=> 1,
	},
	'invalid'	=> {
		pod		=> "=head1 NAME\n\nHello from Foobar! Please visit L<More::Fluffy::Stuff> for more info!",
		actual_ok	=> 0,
	},
	'invalid_sec'	=> {
		pod		=> "=head1 NAME\n\nHello from L</Foobar>!",
		actual_ok	=> 0,
	},
	'invalid_sec_quo'=> {
		pod		=> "=head1 NAME\n\nHello from L<\"Foobar\">!",
		actual_ok	=> 0,
	},
	'pass_sec'	=> {
		pod		=> "=head1 NAME\n\nHello from L</Zonkers>!\n\n=head1 Zonkers\n\nThis is the Foobar!",
		actual_ok	=> 1,
	},
	'pass_sec2'	=> {
		pod		=> "=head1 NAME\n\nHello from us!\n\n=head1 Zonkers\n\nThis is the Foobar!\n\n=head1 Welcome\n\nL</Zonkers>",
		actual_ok	=> 1,
	},
	'pass_sec_quo'	=> {
		pod		=> "=head1 NAME\n\nHello from L<\"Zonkers\">!\n\n=head1 Zonkers\n\nThis is the Foobar!",
		actual_ok	=> 1,
	},
	'pass_sec2_quo'	=> {
		pod		=> "=head1 NAME\n\nHello from us!\n\n=head1 Zonkers\n\nThis is the Foobar!\n\n=head1 Welcome\n\nL<\"Zonkers\">",
		actual_ok	=> 1,
	},
	'pass_man'	=> {
		pod		=> "=head1 NAME\n\nHello from L<man(1)>!",
		actual_ok	=> 1,
	},
	'invalid_man'	=> {
		pod		=> "=head1 NAME\n\nHello from L<famboozled(9)>!",
		actual_ok	=> 0,
	},
);

plan tests => ( scalar keys %tests ) *  5;

foreach my $t ( keys %tests ) {
	# Add some generic data
	if ( $tests{ $t }{ actual_ok } ) {
		$tests{ $t }{ ok } = 1;
	} else {
		$tests{ $t }{ ok } = 0;
	}
	$tests{ $t }{ depth } = 1;

	my( $premature, @results ) = eval {
		run_tests(
			sub {
				my( $fh, $filename ) = tempfile( UNLINK => 1 );
				$fh->autoflush( 1 );
				print $fh delete $tests{ $t }{ pod };
				my $checker = Test::Pod::LinkCheck->new;
				$checker->pod_ok( $filename );
				undef $checker;
			},
		);
	};

	ok( ! $@, "$t completed" );
	is( scalar @results, 1, "$t contained 1 test" );

	# compare the result
	foreach my $res ( keys %{ $tests{ $t } } ) {
		is( $results[0]->{ $res }, $tests{ $t }{ $res }, "$res for $t" );
	}
}

done_testing();

