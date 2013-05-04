#!/usr/bin/perl
use lib 'lib';
use lib 'debug';
use strictures 1;
use v5.14;
use all 'Node::*';
use Parse::RecDescent;
use File::Slurp;
use Docopt::Docopt qw|docopt|; # not repeating... right

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

# use DDP; p $tests;
# use Data::Dumper; $Data::Dumper::Indent = 2; print Dumper($tests);
# use SeeTree; SeeTree::please($tests);

# say "\n\ntest count: ", 0+ @$tests;
# use DDP; p $tests->[68];
# say $tests->[160]{docopt_string};

# $tests = [ @$tests[0 .. 67, 80 .. 100] ];

testcases_report(perform_tests($tests));

# sub docopt { return {}; } # stub for the actual docopt

# perform_tests([ $tests->[68] ]);

sub perform_tests
{
    my $tests = shift;
    my @test_outcome_list;

    for my $i (0 .. $#{$tests})
    {
        my $io_count = @{ $tests->[$i]{io_list} };
        my $passing_ios = 0;
        my $io_number = 0;
        for my $io (@{ $tests->[$i]{io_list} })
        {
            $io_number++;
            my @args = split /\s+/, $io->{input};

            eval
            {
                $passing_ios += are_hashes_equal($io->{output}, docopt($tests->[$i]{docopt_string}, args => \@args));
            };
            if ($@)
            {
                # print $@;
                say "test ", $i + 1, " io# $io_number failed from parser errors";
            }
        }
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

    say 'failing tests (ranges are inclusive):';
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
