#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';
use v5.14;

use Docopt::Docopt;

my $usage = <<'USAGE';
Usage:
    testcases.pl -h | --help
    testcases.pl run
    testcases.pl [ (-s | --show) <test_number> ]

Options:
    -o, --open  Sections don't currently work. [default: 1234]

Advanced Options:
    --whatever  Ignore this.

USAGE

print $usage;
my $op = docopt($usage);
use DDP; p $op;
