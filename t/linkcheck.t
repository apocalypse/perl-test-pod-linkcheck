#!/usr/bin/perl

use Test::More;

eval "use Test::Pod::LinkCheck";
if ( $@ ) {
	plan skip_all => 'Test::Pod::LinkCheck required for testing POD';
} else {
	all_pod_files_ok();
}
