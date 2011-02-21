#!/usr/bin/perl

use Test::More;
use Test::Pod::LinkCheck qw( all_pod_ok );

# run the test!
TODO: {
	local $TODO = "Maybe the default backend is not configured properly...";
	eval {
		all_pod_ok();
	};
}
