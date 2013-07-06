package UsageParser;
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

use Cwd (); use File::Basename ();
my $__DIR__  = File::Basename::dirname(Cwd::abs_path(__FILE__));


# if running as a script
if (!caller)
{
    # $RD_HINT = 1;
    # $RD_TRACE = 1;

    my $usage_string = join '', <DATA>;
    my $usage = parse_usage($usage_string);
    use Data::Dumper; $Data::Dumper::Indent = 2; say Dumper($usage);
}


sub parse_usage
{
    my $usage_string = shift;

    state $skip_spaces_and_comments = qr{
        (?mxs:
            \s+     # skip whitespace including \n
          | \# .*?$ # skip line comments
        )*
    }x;
    $Parse::RecDescent::skip = $skip_spaces_and_comments;
    my $grammar      = read_file("$__DIR__/Usage.grammar");
    my $usage_parser = new Parse::RecDescent($grammar);
    die '[docopt] error in Usage.grammar' if !$usage_parser;

    my $usage = $usage_parser->parse($usage_string);
    die '[docopt] error: could not parse the usage section' if !defined $usage;

    for my $usage_pattern (@{ $usage->{usage_pattern_list} })
    {
        _simplify_usage_element_list($usage_pattern->{usage_element_list});
    }

    return $usage;
}

sub _simplify_usage_element_list
{
    my $usage_element_list = shift;
    # _simplify_short_options($usage_element_list);
    # _simplify_long_options($usage_element_list);
}

# Turns sequential short options, i.e -c -z -f into the single short option -czf
#
sub _simplify_short_options
{
    my $usage_element_list = shift;

    my $i = 0;
    while ($i < @{ $usage_element_list })
    {
        my $element = $usage_element_list->[$i];
        my $ref = ref $element;
        if ($ref eq 'ShortOption')
        {
            my $simpler_short_option = $element->{name};
            if (defined $usage_element_list->[$i + 1] && ref $usage_element_list->[$i + 1] eq 'ShortOption')
            {
                my $offset = $i;
                my $length = $i + 1;
                while (defined $usage_element_list->[$length] && ref $usage_element_list->[$length] eq 'ShortOption')
                {
                    $simpler_short_option .= $usage_element_list->[$length]{name};
                    $length++;
                }
                my $simpler_short_option = bless({ name => $simpler_short_option }, 'ShortOption');
                # say "\$offset: $offset; \$length: $length; \$i = $i";
                splice @{ $usage_element_list }, $offset, $length - $offset, $simpler_short_option;
            }
        }
        elsif ($ref eq 'Optional' || $ref eq 'Required') { _simplify_short_options($element->{usage_element_list}); }
        elsif ($ref eq 'Or')
        {
            for my $or_element (@{ $element->{or_list} })
            {
                my $ref = ref $or_element;
                if ($ref eq 'ARRAY')
                {
                    _simplify_short_options($or_element);
                }
                elsif ($ref eq 'Optional' || $ref eq 'Required')
                {
                    _simplify_short_options($or_element->{usage_element_list});
                }
            }
        }

        $i++;
    }
}

# Turns a long option without an argument (ex: --help) followed by an argument (ex: ME)
# i.e --help ME into the equivalent long option with an argument: --help=ME
# or likewise --help <me> into --help=<me>
#
sub _simplify_long_options
{
    my $usage_element_list = shift;

    my $i = 0;
    while ($i < @{ $usage_element_list })
    {
        my $element = $usage_element_list->[$i];
        if
        (
             ref $element eq 'LongOption'
         && !defined $element->{argument}
         &&  defined $usage_element_list->[$i + 1]
         &&  ref $usage_element_list->[$i + 1] eq 'Argument'
        )
        {
            $element->{argument} = $usage_element_list->[$i + 1];
            splice @{ $usage_element_list }, $i + 1, 1;
        }
        # elsif (ref $element eq 'Optional')
        # {
        #     _simplify_long_options($element->{usage_element_list});
        # }
        $i++;
    }
}

1;


# 1
# usage pattern with no options, i.e:
# script.pl
#

# 2
# usage pattern with short options:
# script.pl -x
# script.pl -x -y
# script.pl -A
# script.pl -_
#

# 3
# usage pattern with long options:
# script.pl --help

# 4
# usage pattern with long options with arguments:
# script.pl --help=<me>
# script.pl --help=YOURSELF
# script.pl --help <us>

# 5
# usage pattern with arguments:
# script.pl <some-arg>
# script.pl <another arg>
# script.pl FILE
# script.pl MY_FILE
# script.pl MY-FILE

# 6
# usage pattern with commands
# script.pl add
# script.pl stop.it
# script.pl vector mul

# 7
# usage pattern with a dobule dash:
# script.pl --

# 8
# usage pattern with a single dash:
# script.pl -

# 9
# usage pattern with tokens
# script.pl ,
# script.pl <
# script.pl ...
# script.pl +
# script.pl >>

# 10
# usage pattern with an 'or' ('|', aka pipe)
# script.pl -h | --help
# script.pl -h | --help | -o | --open

# 11
# usage pattern with optional elements
# script.pl [ -h ]
# script.pl [ <FILE> ]

# 12
# usage pattern with required elements
# actually all elements outside of [] are required
# script.pl (<FILE>)

# 13
# usage pattern with  '...', i.e repeat:
# script.pl -v...
# script.pl FILE ...

# 14
# usage pattern with mixed elements
# script.pl [--version] [--exec-path=<path>] [--html-path]
# script.pl <value> ( ( + | - | * | / ) <value> )...
# script.pl <name> = <value>
# script.pl <value> ( ( AA | BB | CC | DD ) <value> )...
# script.pl -o --
# script.pl --list-of=A
# script.pl -a FILE
# script.pl -o <FILY> FILE
# script.pl -o FILE . --flag
# script.pl [ -o FILE ]
# script.pl (A) | ((B))
# script.pl -o (((FILE)))
# script.pl <name> (<file> = <file>) ...
# script.pl [-v -q -r -h] [FILE] ...
# script.pl (--left | --right) CORRECTION FILE
# script.pl go [go]
# script.pl <function> <value> [( , <value> )]...
# script.pl [--moored | --drifting]
# script.pl [FILE ...]
# script.pl -a -o | -b
# script.pl (-a -o) | -b
# script.pl <file> <file>
# script.pl --lo1=<file> --lo2=FILE
# script.pl serial <port> [--baud=9600] [--timeout=<seconds>]
# script.pl -h | --help | --version
# script.pl tcp <host> <port> [--timeout=<seconds>]
# script.pl --long-op=<file> ...
# script.pl FILE [ -o | <file> ] F2
# naval_fate.pl ship shoot <x> <y>
# naval_fate.pl mine (set|remove) <x> <y> [--moored|--drifting]
# naval_fate.pl --version
# naval_fate.pl ship <name> move <x> <y> [--speed=<kn>]
# naval_fate.pl ship new <name>...
# script.pl [-c <name>=<value>] [--help]
# script.pl [-c <name> = <value>] [--help]
# script.pl <num> [ + <num> ] ...
# script.pl [ ]
# script.pl ()


__DATA__
Usage:
    script.pl [ --help ]
