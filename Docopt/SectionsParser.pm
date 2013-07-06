package SectionsParser;
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK);
BEGIN
{
    require Exporter;
    $VERSION   = 1.00;
    @ISA       = qw|Exporter|;
    @EXPORT    = qw||;
    @EXPORT_OK = qw||;
}

use strict;
use warnings;
use v5.10;
use Parse::RecDescent;
use File::Slurp;
use Regexp::Common;

use Cwd (); use File::Basename ();
my $__DIR__  = File::Basename::dirname(Cwd::abs_path(__FILE__));


# if running as a script
if (!caller)
{
    my $docopt_string = join '', <DATA>;
    my ($usage_string, $sections_string) = get_usage_string_and_sections_string($docopt_string);
    # say $usage_string;
    # say $sections_string;
    # exit 1;

    my $sections = parse_sections($sections_string);
    for my $section (@$sections)
    {
        for my $row (@{ $section->{rows} })
        {
            my $default_value = extract_default_value_from_description($row->{option_description});
            $row->{default_value} = $default_value;
        }
    }
    use Data::Dumper; $Data::Dumper::Indent = 2; print Dumper($sections);
}


sub parse_sections
{
    state $skip_spaces_and_comments = qr{
        (?mxs:
            \s+     # skip whitespace including \n
          | \# .*?$ # skip line comments
        )*
    }x;

    $Parse::RecDescent::skip = $skip_spaces_and_comments;
    # $RD_HINT = 1;
    # $RD_TRACE = 1;

    state $grammar = read_file("$__DIR__/Section.grammar");
    state $section_parser = new Parse::RecDescent($grammar);
    die '[docopt] error in Section.grammar' if !$section_parser;

    my $sections_string = shift;
    # say $sections_string;

    my @sections;
    if ($sections_string ne '')
    {
        # Turns the $sections_string into an array each element
        # of which is a single section (string). This is required
        # because the $section_parser can only parse
        # a single section at a time.
        #
        my @sections_lines = split /\n/, $sections_string;
        my $i = 0;
        OUTER: while ($i < @sections_lines)
        {
            my $sections_line = $sections_lines[$i];

            if ($sections_line =~ /^[^:]+:$/)
            {
                push @sections, [$sections_line];
                $i++;
                $sections_line = $sections_lines[$i];
                INNER: while ($sections_line !~ /^[^:]+:$/)
                {
                    push @{ $sections[-1] }, $sections_line;
                    $i++;
                    last OUTER if $i >= @sections_lines;
                    $sections_line = $sections_lines[$i];
                }
                $i--;
            }
            $i++;
        }
        # use DDP; p @sections;
        @sections = map { join "\n", @$_;  } @sections;
        # use DDP; p @sections;

        @sections = map { $section_parser->parse($_); } @sections;
        # use DDP; p @sections;
        # use Data::Dumper; $Data::Dumper::Indent = 2; print Dumper(@sections);

        # Gets rid of each section's last row because it's attributes are undef (a grammar "feature" :P)
        for my $section (@sections)
        {
            pop @{ $section->{rows} };
        }
        # use Data::Dumper; $Data::Dumper::Indent = 2; print Dumper(@sections);
    }

    return \@sections;
}

sub get_usage_string_and_sections_string
{
    my $docopt_string = shift;

    # Extract the $usage_string and $sections_string from the docopt string.
    #
    # An example $usage_string:
    #
    # Usage:
    #     naval_fate.pl ship new <name>...
    #     naval_fate.pl ship <name> move <x> <y> [--speed=<kn>]
    #     naval_fate.pl ship shoot <x> <y>
    #
    #
    # An example $sections_string:
    #
    # Some section name:
    #     -s, --ome-flags=<with-args>
    #
    # Another section:
    #     -w, --ith-its-own-flags=<and-args>
    #     this row has no options, only a description =)
    #
    #
    # They could be mixed like so:
    #
    # Some section name:
    #     -s, --ome-flags=<with-args>
    #
    # Usage:
    #     naval_fate.pl ship new <name>...
    #     naval_fate.pl ship <name> move <x> <y> [--speed=<kn>]
    #     naval_fate.pl ship shoot <x> <y>
    #
    # Another section:
    #     -w, --ith-its-own-flags=<and-args>
    #     this row has no options, only a description =)
    #
    my @docopt_lines = split /\n/, $docopt_string;
    my @usage_string_lines;
    my @sections_string_lines;
    my $i = 0;
    my $usage_string_found = 0;
    while ($i < @docopt_lines)
    {
        my $docopt_line = $docopt_lines[$i];

        # Found the start of the $usage_string
        if (!$usage_string_found && $docopt_line =~ /^\s*usage\s*:\s*$/i)
        {
            push @usage_string_lines, $docopt_line;
            $i++;
            $docopt_line = $docopt_lines[$i];
            while ($docopt_line !~ /^[^:]+:$/)
            {
                push @usage_string_lines, $docopt_line;
                $i++;
                last if $i >= @docopt_lines;
                $docopt_line = $docopt_lines[$i];
            }
            $i--;
            $usage_string_found = 1;
            next;
        }

        # We found a section.
        if ($docopt_line =~ /^[^:]+:$/)
        {
            while (1)
            {
                push @sections_string_lines, $docopt_line;
                $i++;
                last if $i >= @docopt_lines;
                $docopt_line = $docopt_lines[$i];

                if ($docopt_line =~ /^\s*usage\s*:\s*$/i)
                {
                    $i--;
                    last;
                }
            }
        }

        $i++;
    }

    my $usage_string    = join "\n", @usage_string_lines;
    # say $usage_string;
    my $sections_string = join "\n", @sections_string_lines;
    # say $sections_string;

    return $usage_string, $sections_string;
}

# Example description:
# Speed in knots [default: 10].
#
sub extract_default_value_from_description
{
    my $description = shift;

    my ($default_value) = $description =~ /($RE{balanced}{-parens=>'[]'})/;
    return if !defined $default_value;

    # get rid of the []
    $default_value = substr $default_value, 1;
    chop $default_value;

    $default_value =~ s/\s*default\s*:\s*//;
    if ($default_value =~ ',')
    {
        # looks like a list
        $default_value = [split /\s*,\s*/, $default_value];
    }
    else
    {
        # trim
        s/^\s+//, s/\s+$// for $default_value;
    }

    return $default_value;
}

#     naval_fate.py mine (set|remove) <x> <y> [--moored | --drifting]
#     naval_fate.py (-h | --help)
#     naval_fate.py --version



#     --moored        Moored (anchored) mine.
#     --drifting      Drifting mine.
#
# Some section:
#     -n, --name=<DA FUQ>   Description =)
#

1;

__DATA__
Options:
    --speed=<kn>    Speed in knots [default: 10, 20, 30, 40].
    -h, --help      Show this screen.
    --version       Show version. [default: 'haha']

Whatever:
    --helo  =)

Usage:
    naval_fate.py ship new <name>...
    naval_fate.py ship <name> move <x> <y> [--speed=<kn>]
    naval_fate.py ship shoot <x> <y>

Example:
        reaver -i mon0 -b 00:90:4C:C1:AC:21 -vv
