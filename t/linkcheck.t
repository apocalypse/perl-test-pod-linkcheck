#!/usr/bin/perl

use Test::Pod::LinkCheck;

# run the test!
Test::Pod::LinkCheck->new->all_pod_ok;
