package Test::Pod::LinkCheck;

# ABSTRACT: Tests POD for invalid links

# Import the modules we need
use Moose 1.01;
use Test::Pod 1.44 ();
use App::PodLinkCheck::ParseLinks 4;

# setup our tests and etc
use Test::Builder 0.94;
my $Test = Test::Builder->new;

# export our 2 subs
use base qw( Exporter );
our @EXPORT_OK = qw( pod_ok all_pod_ok );

=attr check_cpan

If disabled, this module will not check the CPAN module database to see if a link is a valid CPAN module or not. As of now
this module only supports L<CPANPLUS> as the backend, others may be added.

The default is: true

=attr cpan_backend

Selects the CPAN backend to use for querying modules. The available ones are: CPANPLUS, CPAN, and CPANSQLite.

The default is: CPANPLUS

=attr cpan_section_err

If enabled, a link pointing to a CPAN module's specific section is treated as an error. Since the module isn't installed we
are unable to verify the section actually exists.

The default is: false

=attr verbose

If enabled, this module will print extra diagnostics for the links it's checking.

The default is: true

=cut

has 'check_cpan' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 1,
);

{
	use Moose::Util::TypeConstraints 1.01;

	has 'cpan_backend' => (
		is	=> 'rw',
		isa	=> enum( [ qw( CPANPLUS CPAN CPANSQLite ) ] ),
		default	=> 'CPANPLUS',
		trigger => \&_clean_backend,
	);

	sub _clean_backend {
		my( $self, $new, $old ) = @_;

		# Just clear the cpan backend
		$self->_cache->{'cpan'} = {};
	}
}

has 'cpan_section_err' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 0,
);

has 'verbose' => (
	is	=> 'rw',
	isa	=> 'Bool',
	default	=> 1,
);

has '_cache' => (
	is	=> 'ro',
	isa	=> 'HashRef',
	default	=> sub { return {
		'cpan'		=> {},
		'man'		=> {},
		'pod'		=> {},
		'section'	=> {},
	} },
);

=method pod_ok

Accepts the filename to check, and an optional test name.

This method will pass the test if there is no POD links present in the POD or if all links are not an error. Furthermore, if the POD was
malformed as reported by L<Pod::Simple>, the test will fail and not attempt to check the links.

When it fails, this will show any failing links as diagnostics. Also, some extra information is printed if verbose is enabled.

The default test name is: "LinkCheck test for FILENAME"

=cut

sub pod_ok {
	my $self = shift;
	my $file = shift;

	if ( ! ref $self ) {	# Allow function call
		$file = $self;
		$self = __PACKAGE__->new;
	}

	my $name = @_ ? shift : "LinkCheck test for $file";

	if ( ! -f $file ) {
		$Test->ok( 0, $name );

		if ( $self->verbose ) {
			$Test->diag( "Extra: " );
			$Test->diag( " * '$file' does not exist?" );
		}

		return 0;
	}

	# Parse the POD!
	my $parser = App::PodLinkCheck::ParseLinks->new( {} );
	my $output;

	# Override some options that the podlinkcheck subclass "helpfully" set for us...
	$parser->output_string( \$output );
	$parser->complain_stderr( 0 );
	$parser->no_errata_section( 0 );
	$parser->no_whining( 0 );
	$parser->parse_file( $file );

	# is POD well-formed?
	if ( $parser->any_errata_seen ) {
		$Test->ok( 0, $name );

		if ( $self->verbose ) {
			$Test->diag( "Extra: " );
			$Test->diag( " * Unable to parse POD in '$file'" );

			# TODO ugly, but there is no other way to get at it?
			## no critic ( ProhibitAccessOfPrivateData )
			foreach my $l ( keys %{ $parser->{errata} } ) {
				$Test->diag( " * errors seen in line $l:" );
				$Test->diag( "   * $_" ) for @{ $parser->{errata}{$l} };
			}
		}

		return 0;
	}

	# Did we see POD in the file?
	if ( $parser->doc_has_started ) {
		my( $err, $diag ) = $self->_analyze( $parser );

		if ( scalar @$err > 0 ) {
			$Test->ok( 0, $name );
			$Test->diag( "Erroneous links: " );
			$Test->diag( " * $_" ) for @$err;

			if ( $self->verbose and @$diag ) {
				$Test->diag( "Extra: " );
				$Test->diag( " * $_" ) for @$diag;
			}

			return 0;
		} else {
			$Test->ok( 1, $name );

			if ( $self->verbose and @$diag ) {
				$Test->diag( "Extra: " );
				$Test->diag( " * $_" ) for @$diag;
			}
		}
	} else {
		$Test->ok( 1, $name );

		if ( $self->verbose ) {
			$Test->diag( "Extra: " );
			$Test->diag( " * There is no POD in '$file' ?" );
		}
	}

	return 1;
}

=method all_pod_ok

Accepts an optional array of files to check. By default it uses all POD files in your distribution.

This method is what you will usually run. Every file is passed to the L</pod_ok> function. This also sets the
test plan to be the number of files.

=cut

sub all_pod_ok {
	my $self = shift;
	my @files = @_ ? @_ : Test::Pod::all_pod_files();

	if ( ! defined $self or ! ref $self ) {	# Allow function call
		unshift( @files, $self ) if defined $self;
		$self = __PACKAGE__->new;
	}

	$Test->plan( tests => scalar @files );

	my $ok = 1;
	foreach my $file ( @files ) {
		$self->pod_ok( $file ) or undef $ok;
	}

	return $ok;
}

sub _analyze {
	my( $self, $parser ) = @_;

	my $file = $parser->source_filename;
	my $links = $parser->links_arrayref;
	my $own_sections = $parser->sections_hashref;
	my( @errors, @diag );

	foreach my $l ( @$links ) {
		## no critic ( ProhibitAccessOfPrivateData )
		my( $type, $to, $section, $linenum, $column ) = @$l;
		push( @diag, "$file:$linenum:$column - Checking link '$type/" . ( defined $to ? $to : '' ) . "/" .
			( defined $section ? $section : '' ) . "'" ) if $ENV{'TEST_VERBOSE'};

		# What kind of link?
		if ( $type eq 'man' ) {
			if ( ! $self->_known_manpage( $to ) ) {
				push( @errors, "$file:$linenum:$column - Unknown manpage '$to'" );
			}
		} elsif ( $type eq 'pod' ) {
			# do we have a to/section?
			if ( defined $to ) {
				if ( defined $section ) {
					# Do we have this file installed?
					if ( ! $self->_known_podlink( $to, $section ) ) {
						# Is it a CPAN module?
						my $res = $self->_known_cpan( $to );
						if ( defined $res ) {
							if ( $res ) {
								# if true, treat cpan sections as errors because we can't verify if section exists
								if ( $self->cpan_section_err ) {
									push( @errors, "$file:$linenum:$column - Unable to verify pod link '$to/$section' because the CPAN module is not installed" );
								}
							} else {
								push( @errors, "$file:$linenum:$column - Unknown pod link '$to/$section' - module doesn't exist in CPAN" );
							}
						} else {
							push( @errors, "$file:$linenum:$column - Unknown pod link '$to/$section' - unable to check CPAN" );
						}
					}
				} else {
					# Do we have this file installed?
					if ( ! $self->_known_podfile( $to ) ) {
						# Sometimes we find a manpage but not the pod...
						if ( ! $self->_known_manpage( $to ) ) {
							# Is it a CPAN module?
							my $res = $self->_known_cpan( $to );
							if ( defined $res ) {
								if ( ! $res ) {
									# Check for internal section
									if ( exists $own_sections->{ $to } ) {
										push( @diag, "$file:$linenum:$column - Internal section link - recommend 'L</$to>'" );
									} else {
										push( @errors, "$file:$linenum:$column - Unknown pod file '$to' - module doesn't exist in CPAN" );
									}
								}
							} else {
								# Check for internal section
								if ( exists $own_sections->{ $to } ) {
									push( @diag, "$file:$linenum:$column - Internal section link - recommend 'L</$to>'" );
								} else {
									push( @errors, "$file:$linenum:$column - Unknown pod link '$to' - unable to check CPAN" );
								}
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

	return( \@errors, \@diag );
}

sub _known_manpage {
	## no critic ( ProhibitAccessOfPrivateData )
	my( $self, $page ) = @_;
	my $cache = $self->_cache->{'man'};

	if ( ! exists $cache->{ $page } ) {
		my @manargs;
		if ( $page =~ /(.+)\s*\((.+)\)$/ ) {
			@manargs = ($2, $1);
		} else {
			@manargs = ($page);
		}

		require Capture::Tiny;
		$cache->{ $page } = Capture::Tiny::capture_merged( sub {
			system( 'man', @manargs );
		} );

		# We need at least 5 newlines to guarantee a real manpage
		if ( ( $cache->{ $page } =~ tr/\n// ) > 5 ) {
			$cache->{ $page } = 1;
		} else {
			$cache->{ $page } = 0;
		}
	}

	return $cache->{ $page };
}

sub _known_podfile {
	## no critic ( ProhibitAccessOfPrivateData )
	my( $self, $link ) = @_;
	my $cache = $self->_cache->{'pod'};

	if ( ! exists $cache->{ $link } ) {
		# Is it a plain POD file?
		require Pod::Find;
		my $filename = Pod::Find::pod_where( {
			'-inc'	=> 1,
		}, $link );
		if ( defined $filename ) {
			$cache->{ $link } = $filename;
		} else {
			# It might be a script...
			require File::Spec;
			require Config;
			foreach my $dir ( split /\Q$Config::Config{'path_sep'}/o, $ENV{'PATH'} ) {
				my $filename = File::Spec->catfile( $dir, $link );
				if ( -e $filename ) {
					$cache->{ $link } = $filename;
					last;
				}
			}
			if ( ! exists $cache->{ $link } ) {
				$cache->{ $link } = 0;
			}
		}
	}

	return $cache->{ $link };
}

sub _known_cpan {
	## no critic ( ProhibitAccessOfPrivateData )
	my( $self, $module ) = @_;

	# Do we even check CPAN?
	if ( ! $self->check_cpan ) {
		return undef;
	}

	# is the answer cached already?
	if ( exists $self->_cache->{'cpan'}{ $module } ) {
		return $self->_cache->{'cpan'}{ $module };
	}

	# Select the backend?
	if ( $self->cpan_backend eq 'CPANPLUS' ) {
		return $self->_known_cpan_cpanplus( $module );
	} elsif ( $self->cpan_backend eq 'CPAN' ) {
		return $self->_known_cpan_cpan( $module );
	} elsif ( $self->cpan_backend eq 'CPANSQLite' ) {
		return $self->_known_cpan_cpansqlite( $module );
	} else {
		die "Unknown backend: " . $self->cpan_backend;
	}
}

sub _known_cpan_cpanplus {
	my( $self, $module ) = @_;
	my $cache = $self->_cache->{'cpan'};

	# init the backend ( and set some options )
	if ( ! exists $cache->{'.'} ) {
		eval {
			# Wacky format so dzil will not autoprereq it
			require 'CPANPLUS/Backend.pm'; require 'CPANPLUS/Configure.pm';

			my $cpanconfig = CPANPLUS::Configure->new;
			$cpanconfig->set_conf( 'verbose' => 0 );
			$cpanconfig->set_conf( 'no_update' => 1 );

			# ARGH, CPANIDX doesn't work well with this kind of search...
			# TODO check if it's still true?
			if ( $cpanconfig->get_conf( 'source_engine' ) =~ /CPANIDX/ ) {
				$cpanconfig->set_conf( 'source_engine' => 'CPANPLUS::Internals::Source::Memory' );
			}

			# silence CPANPLUS!
			eval "no warnings 'redefine'; sub Log::Message::store { return }";
			local $SIG{'__WARN__'} = sub { return };
			$cache->{'.'} = CPANPLUS::Backend->new( $cpanconfig );
		};
		if ( $@ ) {
			warn "Unable to load CPANPLUS - switching to CPAN ( $@ )" if $self->verbose;
			$self->cpan_backend( 'CPAN' );
			return $self->_known_cpan( $module );
		}
	}

	my $result = undef;
	eval { local $SIG{'__WARN__'} = sub { return }; $result = $cache->{'.'}->parse_module( 'module' => $module ) };
	if ( ! $@ and defined $result ) {
		$cache->{ $module } = 1;
	} else {
		$cache->{ $module } = 0;
	}

	return $cache->{ $module };
}

sub _known_cpan_cpansqlite {
	my( $self, $module ) = @_;
	my $cache = $self->_cache->{'cpan'};

	# init the backend ( and set some options )
	if ( ! exists $cache->{'.'} ) {
		eval {
			# Wacky format so dzil will not autoprereq it
			require 'CPAN.pm'; require 'CPAN/SQLite.pm';

			# TODO this code stolen from App::PodLinkCheck
			# not sure how far back this will work, maybe only 5.8.0 up
			if ( ! $CPAN::Config_loaded && CPAN::HandleConfig->can( 'load' ) ) {
				# fake $loading to avoid running the CPAN::FirstTime dialog -- is this the right way to do that?
				local $CPAN::HandleConfig::loading = 1;
				CPAN::HandleConfig->load;
			}

			$cache->{'.'} = CPAN::SQLite->new;
		};
		if ( $@ ) {
			$self->check_cpan( 0 );
			delete $cache->{'.'} if exists $cache->{'.'};
			warn "Unable to load CPANSQLite - disabling CPAN searches! ( $@ )" if $self->verbose;
			return undef;
		}
	}

	my $result = undef;
	eval { local $SIG{'__WARN__'} = sub { return }; $result = $cache->{'.'}->query( 'mode' => 'module', name => $module, max_results => 1 ) };
	if ( ! $@ and defined $result ) {
		$cache->{ $module } = 1;
	} else {
		$cache->{ $module } = 0;
	}

	return $cache->{ $module };
}

sub _known_cpan_cpan {
	my( $self, $module ) = @_;
	my $cache = $self->_cache->{'cpan'};

	# init the backend ( and set some options )
	if ( ! exists $cache->{'.'} ) {
		eval {
			# Wacky format so dzil will not autoprereq it
			require 'CPAN.pm';

			# TODO this code stolen from App::PodLinkCheck
			# not sure how far back this will work, maybe only 5.8.0 up
			if ( ! $CPAN::Config_loaded && CPAN::HandleConfig->can( 'load' ) ) {
				# fake $loading to avoid running the CPAN::FirstTime dialog -- is this the right way to do that?
				local $CPAN::HandleConfig::loading = 1;
				CPAN::HandleConfig->load;
			}

			# figure out the access method
			if ( defined $CPAN::META && %$CPAN::META ) {
	 			# works already!
			} elsif ( ! CPAN::Index->can('read_metadata_cache') ) {
				# Argh, we can't use it...
				die "Unable to use CPAN.pm metadata cache!";
			} else {
				# try the .cpan/Metadata even if CPAN::SQLite is installed, just in
				# case the SQLite is not up-to-date or has not been used yet
				local $CPAN::Config->{use_sqlite} = $CPAN::Config->{use_sqlite} = 0;	# stupid used once warning...
				CPAN::Index->read_metadata_cache;
				if ( defined $CPAN::META && %$CPAN::META ) {
					# yay, works!
				} else {
					die "Unable to use CPAN.pm metadata cache!";
				}
			}

			# Cache is ready
			$cache->{'.'} = $CPAN::META->{'readwrite'}->{'CPAN::Module'};
		};
		if ( $@ ) {
			warn "Unable to load CPAN - switching to CPANSQLite ( $@ )" if $self->verbose;
			$self->cpan_backend( 'CPANSQLite' );
			return $self->_known_cpan( $module );
		}
	}

	if ( exists $cache->{'.'}{ $module } ) {
		$cache->{ $module } = 1;
	} else {
		$cache->{ $module } = 0;
	}

	return $cache->{ $module };
}

sub _known_podlink {
	## no critic ( ProhibitAccessOfPrivateData )
	my( $self, $link, $section ) = @_;

	# First of all, does the file exists?
	my $filename = $self->_known_podfile( $link );
	return 0 if ! defined $filename;

	# Okay, get the sections in the file and see if the link matches
	my $file_sections = $self->_known_podsections( $filename );
	if ( defined $file_sections and exists $file_sections->{ $section } ) {
		return 1;
	} else {
		return 0;
	}
}

sub _known_podsections {
	## no critic ( ProhibitAccessOfPrivateData )
	my( $self, $filename ) = @_;
	my $cache = $self->_cache->{'sections'};

	if ( ! exists $cache->{ $filename } ) {
		# Okay, get the sections in the file
		require App::PodLinkCheck::ParseSections;
		my $parser = App::PodLinkCheck::ParseSections->new( {} );
		$parser->parse_file( $filename );
		$cache->{ $filename } = $parser->sections_hashref;
	}

	return $cache->{ $filename };
}

# from Moose::Manual::BestPractices
no Moose;
__PACKAGE__->meta->make_immutable;

1;

=pod

=for stopwords CPAN foo OO backend env

=head1 SYNOPSIS

	#!/usr/bin/perl
	use strict; use warnings;

	use Test::More;

	eval "use Test::Pod::LinkCheck";
	if ( $@ ) {
		plan skip_all => 'Test::Pod::LinkCheck required for testing POD';
	} else {
		Test::Pod::LinkCheck->new->all_pod_ok;
	}

=head1 DESCRIPTION

This module looks for any links in your POD and verifies that they point to a valid resource. It uses the L<Pod::Simple> parser
to analyze the pod files and look at their links. In a nutshell, it looks for C<LE<lt>FooE<gt>> links and makes sure that Foo
exists. It also recognizes section links, C<LE<lt>/SYNOPSISE<gt>> for example. Also, manpages are resolved and checked. If you
linked to a CPAN module and it is not installed, it is an error!

This module does B<NOT> check "http" links like C<LE<lt>http://www.google.comE<gt>> in your pod. For that, please check
out L<Test::Pod::No404s>.

Normally, you wouldn't want this test to be run during end-user installation because they might not have the modules installed! It is
HIGHLY recommended that this be used only for module authors' RELEASE_TESTING phase. To do that, just modify the synopsis to
add an env check :)

This module normally uses the OO method to run tests, but you can use the functional style too. Just explicitly ask for the C<all_pod_ok> or
C<pod_ok> function to be imported when you use this module.

	#!/usr/bin/perl
	use strict; use warnings;
	use Test::Pod::LinkCheck qw( all_pod_ok );
	all_pod_ok();

=head1 SEE ALSO
L<App::PodLinkCheck>
L<Pod::Checker>
L<Test::Pod::No404s>

=cut
