#!/usr/bin/perl
use strict;
use warnings;
use v5.10;
use Parse::RecDescent;
use File::Slurp;
use lib '..';
use Docopt::Docopt; # qw|docopt|; # not repeating... right

my $skip_spaces_and_comments = qr{
    (?mxs:
        \s+     # skip whitespace including \n
      | \# .*?$ # skip line comments
    )*
}x;

$Parse::RecDescent::skip = $skip_spaces_and_comments;
# $RD_HINT = 1;
# $RD_TRACE = 1;

my $grammar = read_file('testcases.grammar');
my $parser = new Parse::RecDescent($grammar);

say 'error in grammar' and exit 1 if !$parser;

my $input = join '', <DATA>;
# $input = q|r"""Usage: prog"""|;
$input = read_file('testcases.docopt');

my $tests = $parser->parse($input);
if (!defined($tests)) { say 'could not load tests' and exit 1; }


# Assume the implementation is good enough to handle this input.
my $Usage = <<'END_USAGE';
Usage:
    testcases.pl -h | --help
    testcases.pl run
    testcases.pl [ (-s | --show) <test_number> ]

END_USAGE

my $ops = docopt($Usage, args => \@ARGV);
# use DDP; p $ops;
# exit 1;

if ($ops->{'-s'} || $ops->{'--show'})
{
    my $test_number = 0+$ops->{'<test_number>'};

    if (0 < $test_number && $test_number <= @$tests)
    {
        use DDP; p $tests->[$test_number - 1]; #testcases_report(perform_tests([ $tests->[$see_test] ]));
    }
    else
    {
        say "$test_number is not a valid test number, try: (1, ", 0+@$tests, ')' and exit 1;
    }
}
elsif ($ops->{'run'})
{
    testcases_report(perform_tests($tests));
}
elsif ($ops->{'-h'} || $ops->{'--help'})
{
    print $Usage;
}
else
{
    print $Usage;
}

sub perform_tests
{
    my $tests = shift;
    my @test_outcome_list;

    for my $i (0 .. $#{$tests})
    {
        # ignore this/these tests
        # say "\$i: $i";
        if ($i == (74 - 1) || $i == (155 - 1))
        {
            $test_outcome_list[$i] = 0;
            next;
        }

        my $io_count = @{ $tests->[$i]{io_list} };
        my $passing_ios = 0;
        my $io_number = 0;
        for my $io (@{ $tests->[$i]{io_list} })
        {
            $io_number++;
            my @args = split /\s+/, $io->{input};
            shift @args; # get rid of 'prog'
            # use DDP; p @args;

            eval
            {
                my $docopt_output = docopt($tests->[$i]{docopt_string}, args => \@args);
                # use DDP; p $docopt_output;
                $passing_ios += are_hashes_equal($io->{output}, $docopt_output);
            };
            if ($@)
            {
                print "test #", $i + 1, ": $@";
                if ($@ =~ /^"user-error"/ && $io->{output} eq q|"user-error"|)
                {
                    $passing_ios++;
                }
                else
                {
                    # say "doesn't begging with \"user-error\"";
                    say "test ", $i + 1, " io# $io_number failed from parser errors";
                }
            }
        }
        # say "\$io_count: $io_count; \$passing_ios: $passing_ios";
        $test_outcome_list[$i] = $io_count == $passing_ios;

        # say "test #", $i + 1;
    }

    return \@test_outcome_list;
}


# my $bogus_tests = [0, 0, 1, 1, 0, 0, 0, 1, 0, 1];
# my $bogus_tests = [];
# for (0 .. 99)
# {
#     $bogus_tests->[$_] = int(rand() * 2);
# }
# say join ', ', @$bogus_tests[0 .. 9];
# testcases_report($bogus_tests);

sub testcases_report
{
    my $test_outcome_list = shift;
    my $total_tests       = @$test_outcome_list;
    my $failed_tests      = grep { $_ == 0 } @$test_outcome_list;

    # say "\$total_tests: $total_tests; \$failed_tests: $failed_tests";

    my @failed_tests_ranges;
    my $i = 0;
    while ($i < @$test_outcome_list)
    {
        if ($test_outcome_list->[$i] == 0)
        {
            my $start = $i;
            while (($i + 1) < @$test_outcome_list && $test_outcome_list->[$i + 1] == 0)
            {
                $i++;
            }
            if ($start == $i) { push @failed_tests_ranges, $start + 1; } # not really a range
            else              { push @failed_tests_ranges, ($start + 1) . '-' . ($i + 1); }
        }

        $i++;
    }

    say "\nfailing tests (ranges are inclusive):";
    say join ', ', @failed_tests_ranges;
    say "failed/total: $failed_tests/$total_tests";
}


# my $h1 =
# {
#     a => 'undef',
#     b => [1, 2],
#     c => { a => 1 },
# };
#
# my $h2 =
# {
#     a => 'undef',
#     b => [1, 2],
#     c => { a => 1 },
# };
#
# say +are_hashes_equal($h1, $h2) ? 'hashes are equal' : 'hashes are NOT equal';

sub are_hashes_equal
{
    # say 'are_hashes_equal';
    my ($h1, $h2) = @_;
    my $result    = 1;
    are_hashes_equal_r($h1, $h2, \$result);
    return $result == 1;
}

sub are_hashes_equal_r
{
    my ($h1, $h2, $result) = @_;

    return if $$result == 0;

    my $ref1 = ref $h1;
    my $ref2 = ref $h2;

    if ($ref1 ne $ref2) { $$result = 0; return; }

    if ($ref1 eq 'HASH')
    {
        my @keys1 = sort keys %$h1;
        my @keys2 = sort keys %$h2;

        if (0+@keys1 != 0+@keys2) { $$result = 0; return; }

        for my $i (0 .. $#keys1)
        {
            if ($keys1[$i] ne $keys2[$i]) { $$result = 0; return; }
            are_hashes_equal_r($h1->{ $keys1[$i] }, $h2->{ $keys2[$i] }, $result);
            return if $$result != 1;
        }
    }
    elsif ($ref1 eq 'ARRAY')
    {
        if (0+@$h1 != 0+@$h2) { $$result = 0; return; }

        for my $i (0 .. $#{$h1}) # $#{$h1}, $h1's last index
        {
            are_hashes_equal_r($h1->[$i], $h2->[$i], $result);
            return if $$result != 1;
        }
    }
    else # if ($ref eq '') # SCALAR
    {
        if
        (   (!defined $h1           && !defined $h2)
        ||  (($h1 // '') eq 'undef' && !defined $h2)
        ||  (!defined $h1           && ($h2 // '') eq 'undef')
        )
        {
            # null vs null is a match
        }
        else
        {
            $h1 //= '';
            $h2 //= '';

            $$result = $h1 eq $h2;
        }
    }

    return;
}

sub trim
{
    my $str = shift;
    s/^\s+//, s/\s+$// for $str;
    return $str;
}

__DATA__
r"""Usage: prog [options]

Options: -p PATH

"""
$ prog -p home/
{"-p": "home/"}

$ prog -phome/
{"-p": "home/"}

$ prog -p
"user-error"
