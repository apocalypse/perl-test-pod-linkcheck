#!/usr/bin/perl

use Test::More;
use Test::Pod::LinkCheck;

# run the test!
TODO: {
	local $TODO = "Maybe the default backend is not configured properly...";
	eval {
		Test::Pod::LinkCheck->new->all_pod_ok;
	};
}
