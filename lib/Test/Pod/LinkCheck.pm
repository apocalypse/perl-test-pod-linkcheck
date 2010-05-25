package Test::Pod::LinkCheck;

# ABSTRACT: Tests POD for invalid links

# Import the modules we need
use Test::Pod 1.44 ();
use App::PodLinkCheck::ParseLinks 4;
use App::PodLinkCheck::ParseSections 4;
use Capture::Tiny 0.06 qw( capture_merged );

# setup our tests and etc
use Test::Builder 0.94;
my $Test = Test::Builder->new;

# auto-export our 2 subs
use base qw( Exporter );
our @EXPORT = qw( pod_file_ok all_pod_files_ok ); ## no critic ( ProhibitAutomaticExportation )

sub pod_file_ok {
	my $file = shift;
	my $name = @_ ? shift : "LinkCheck test for $file";

	if ( ! -f $file ) {
		$Test->ok( 0, $name );
		$Test->diag( "$file does not exist" );
		return 0;
	}

	# Parse the POD!
	my $parser = App::PodLinkCheck::ParseLinks->new( {} );
	my $output;
	$parser->output_string( \$output );
	$parser->parse_file( $file );

	# is POD well-formed?
	if ( $parser->any_errata_seen ) {
		$Test->ok( 0, $name );
		$Test->diag( "Unable to parse POD in $file" );
		return 0;
	}

	# Did we see POD in the file?
	if ( $parser->doc_has_started ) {
		my $links = $parser->links_arrayref;
		my $own_sections = $parser->sections_hashref;
		my @errors;

		foreach my $l ( @$links ) {
			my( $type, $to, $section, $linenum, $column ) = @$l;
			$Test->diag( "$file:$linenum:$column - Checking link '$type/" . ( defined $to ? $to : '' ) . "/" .
				( defined $section ? $section : '' ) . "'" ) if $ENV{TEST_VERBOSE};

			# What kind of link?
			if ( $type eq 'man' ) {
				if ( ! _known_manpage( $to ) ) {
					push( @errors, "$file:$linenum:$column - Unknown manpage '$to'" );
				}
			} elsif ( $type eq 'pod' ) {
				# do we have a to/section?
				if ( defined $to ) {
					if ( defined $section ) {
						if ( ! _known_podlink( $to, $section ) ) {
							# TODO Is it on CPAN?
#							if ( _known_cpan( $to ) ) {
#								$Test->diag( "$file:$linenum:$column - Skipping pod link '$to/$section' because it is a valid CPAN module" );
#							} else {
								push( @errors, "$file:$linenum:$column - Unknown pod link '$to/$section'" );
#							}
						}
					} else {
						if ( ! _known_podfile( $to ) ) {
							# Check for internal section
							if ( exists $own_sections->{ $to } ) {
								$Test->diag( "$file:$linenum:$column - Internal section link - recommend 'L</$to>'" );
							} else {
								# Sometimes we find a manpage but not the pod...
								if ( _known_manpage( $to ) ) {
									$Test->diag( "$file:$linenum:$column - Skipping pod link '$to' because it is a valid manpage" );
								} else {
									# TODO Is it on CPAN?
#									if ( _known_cpan( $to ) ) {
#										$Test->diag( "$file:$linenum:$column - Skipping pod link '$to' because it is a valid CPAN module" );
#									} else {
										push( @errors, "$file:$linenum:$column - Unknown pod file '$to'" );
#									}
								}
							}
						}
					}
				} else {
					if ( defined $section ) {
						if ( ! exists $own_sections->{ $section } ) {
							push( @errors, "$file:$linenum:$column - Unknown local pod section '$section'" );
						}
					} else {
						# no to/section eh?
						die "Invalid link: $l";
					}
				}
			} else {
				die "Unknown type: $type";
			}
		}

		if ( scalar @errors > 0 ) {
			$Test->ok( 0, $name );
			foreach my $e ( @errors ) {
				$Test->diag( " * $e" );
			}
			return 0;
		} else {
			$Test->ok( 1, $name );
		}
	} else {
		$Test->ok( 1, $name );
	}

	return 1;
}

sub all_pod_files_ok {
	my @files = @_ ? @_ : Test::Pod::all_pod_files();

	$Test->plan( tests => scalar @files );

	my $ok = 1;
	foreach my $file ( @files ) {
		pod_file_ok( $file ) or undef $ok;
	}

	return $ok;
}

# Cache for manpages
my %CACHE_MAN;

sub _known_manpage {
	my $page = shift;

	if ( ! exists $CACHE_MAN{ $page } ) {
		my @manargs;
		if ( $page =~ /(.+)\s*\((.+)\)$/ ) {
			@manargs = ($2, $1);
		} else {
			@manargs = ($page);
		}

		# TODO doesn't work...
#		require Capture::Tiny;
#		Capture::Tiny->import( qw( capture_merged ) );
		$CACHE_MAN{ $page } = capture_merged {
			system( 'man', @manargs );
		};

		# We need at least 5 newlines to guarantee a real manpage
		if ( ( $CACHE_MAN{ $page } =~ tr/\n// ) > 5 ) {
			$CACHE_MAN{ $page } = 1;
		} else {
			$CACHE_MAN{ $page } = 0;
		}
	}

	return $CACHE_MAN{ $page };
}

# Cache for podfiles
my %CACHE_POD;

sub _known_podfile {
	my $file = shift;

	if ( ! exists $CACHE_POD{ $file } ) {
		# Is it a plain POD file?
		require Pod::Find;
		my $filename = Pod::Find::pod_where( {
			'-inc'	=> 1,
		}, $file );
		if ( defined $filename ) {
			$CACHE_POD{ $file } = $filename;
		} else {
			# It might be a script...
			require File::Spec;
			require Config;
			foreach my $dir ( split /\Q$Config::Config{'path_sep'}/o, $ENV{PATH} ) {
				my $filename = File::Spec->catfile( $dir, $file );
				if ( -e $filename ) {
					$CACHE_POD{ $file } = $filename;
					last;
				}
			}
			if ( ! exists $CACHE_POD{ $file } ) {
				$CACHE_POD{ $file } = 0;
			}
		}
	}

	return $CACHE_POD{ $file };
}

## Cache for cpan modules
#my %CACHE_CPAN;
#
#sub _known_cpan {
#	my $module = shift;
#
#	if ( ! exists $CACHE_CPAN{ $module } ) {
#		# init the backend ( and set some options )
#		require CPANPLUS::Configure;
#		require CPANPLUS::Backend;
#		my $cpanconfig = CPANPLUS::Configure->new;
#		$cpanconfig->set_conf( 'verbose' => 0 );
#		$cpanconfig->set_conf( 'no_update' => 1 );
#
#		# ARGH, CPANIDX doesn't work well with this kind of search...
#		if ( $cpanconfig->get_conf( 'source_engine' ) =~ /CPANIDX/ ) {
#			$cpanconfig->set_conf( 'source_engine' => 'CPANPLUS::Internals::Source::Memory' );
#		}
#
#		my $cpanplus = CPANPLUS::Backend->new( $cpanconfig );
#
#		# silence CPANPLUS!
#		{
#			no warnings 'redefine';
#			sub Log::Message::Handlers::cp_msg { return };
#			sub Log::Message::Handlers::cp_error { return };
#		}
#
#		# Don't let CPANPLUS warnings ruin our day...
#		local $SIG{'__WARN__'} = sub { return };
#		my $module = undef;
#		eval { $module = $cpanplus->parse_module( 'module' => $module ) };
#		if ( ! $@ or defined $module ) {
#			$CACHE_CPAN{ $module } = 1;
#		} else {
#			$CACHE_CPAN{ $module } = 0;
#		}
#	}
#
#	return $CACHE_CPAN{ $module };
#}

sub _known_podlink {
	my( $file, $section ) = @_;

	# First of all, does the file exists?
	if ( ! _known_podfile( $file ) ) {
		return 0;
	}

	# Okay, get the sections in the file and see if the link matches
	my $file_sections = _known_podsections( $CACHE_POD{ $file } );
	if ( defined $file_sections and exists $file_sections->{ $section } ) {
		return 1;
	} else {
		return 0;
	}
}

# Cache for POD sections
my %CACHE_SECTIONS;

sub _known_podsections {
	my( $filename ) = @_;

	if ( ! exists $CACHE_SECTIONS{ $filename } ) {
		# Okay, get the sections in the file
		my $parser = App::PodLinkCheck::ParseSections->new( {} );
		$parser->parse_file( $filename );
		$CACHE_SECTIONS{ $filename } = $parser->sections_hashref;
	}

	return $CACHE_SECTIONS{ $filename };
}

1;

=pod

=head1 SYNOPSIS

	#!/usr/bin/perl
	use strict; use warnings;

	use Test::More;

	eval "use Test::Pod::LinkCheck";
	if ( $@ ) {
		plan skip_all => 'Test::Pod::LinkCheck required for testing POD';
	} else {
		all_pod_files_ok();
	}

=head1 DESCRIPTION

This module looks for any links in your POD and verifies that they point to a valid resource. It uses the L<Pod::Simple> parser
to analyze the pod files and look at their links. Original idea and sample code taken from L<App::PodLinkCheck>, thanks!

In a nutshell, it looks for C<LE<lt>FooE<gt>> links and makes sure that Foo exists. It also recognizes section links, C<LE<lt>/SYNOPSISE<gt>>
for example. Also, manpages are resolved and checked. If you linked to a CPAN module and it is not installed, it is an error!

Normally, you wouldn't want this test to be run during end-user installation because they might not have the modules installed! It is
HIGHLY recommended that this be used only for module authors' RELEASE_TESTING phase. To do that, just modify the synopsis to
add an env check :)

=func pod_file_ok

C<pod_file_ok()> will okay the test if there is no POD links present in the POD or if all links are not an error. Furthermore, if the POD was
malformed as reported by L<Pod::Simple>, the test will fail and not attempt to check the links.

When it fails, C<pod_file_ok()> will show any failing links as diagnostics.

The optional second argument TESTNAME is the name of the test.  If it is omitted, C<pod_file_ok()> chooses a default
test name "LinkCheck test for FILENAME".

=func all_pod_files_ok

This function is what you will usually run. It automatically finds any POD in your distribution and runs checks on them.

Accepts an optional argument: an array of files to check. By default it checks all POD files it can find in the distribution. Every file it finds
is passed to the C<pod_file_ok> function.

This function also sets the test plan to be the number of files found.

=cut
