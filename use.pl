#!/usr/bin/perl
use strict;
use warnings;
use v5.10;
use Parse::RecDescent;
use File::Slurp;
# use lib 'debug';


my $input = join '', <DATA>;
my $useopt = docopt($input, args => \@ARGV);
use DDP; p $useopt;

sub docopt
{
    my $usage_str = shift;
    my %opt_args  = @_;

    my $args = $opt_args{args} // \@ARGV;

    my $skip_spaces_and_comments = qr{
        (?mxs:
            \s+     # skip whitespace including \n
          | \# .*?$ # skip line comments
        )*
    }x;
    $Parse::RecDescent::skip = $skip_spaces_and_comments;
    my $grammar = read_file('docopt.grammar');
    my $parser = new Parse::RecDescent($grammar);
    say 'error in grammar' and exit 1 if !$parser;

    my $t = $parser->parse($usage_str);
    die '[error] could not parse the usage string' if !defined $t;
    say $usage_str;
    say join ' ', @$args;

    my $usage_section = $t->[0];
    # say ref $usage_section;

    my $result = {};
    my $does_pattern_match;
    my $pattern_match_count = 0;
    for my $usage_pattern (@{ $usage_section->{usage_pattern_list} })
    {
        $does_pattern_match = 1;
        use DDP; p $args;
        _handle_usage_pattern($usage_pattern, $result, $args, \$does_pattern_match);
        $pattern_match_count += $does_pattern_match;
    }

    if ($pattern_match_count > 0)
    {
        say 'Okay, a pattern matched';
    }
    else { say 'Should probably show the usage string'; }

    return $result;
}

sub _handle_usage_pattern
{
    my $usage_pattern      = shift;
    my $result             = shift // {};
    my $args               = shift;
    my $does_pattern_match = shift;

    my $usage_element_list = $usage_pattern->{usage_element_list};
    _simplify_usage_element_list($usage_element_list);
    use Data::Dumper; $Data::Dumper::Indent = 2; print Dumper($usage_pattern);
    for my $usage_element (@{ $usage_element_list })
    {
        # last if !defined $arg;
        _handle_usage_element($usage_element, $result, $args, $does_pattern_match);
    }
}

sub _simplify_usage_element_list
{
    my $usage_element_list = shift;

    # Turn sequential short options, i.e -c -z -f into the single
    # short option -czf
    #
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
        elsif ($ref eq 'Optional' || $ref eq 'Required') { _simplify_usage_element_list($element->{usage_element_list}); }
        elsif ($ref eq 'Or')
        {
            for my $or_element (@{ $element->{or_list} })
            {
                if (ref $or_element eq 'ARRAY')
                {
                    _simplify_usage_element_list($or_element);
                }
            }
        }

        $i++;
    }
}

sub _handle_usage_element
{
    my $usage_element        = shift;
    my $result               = shift;
    my $args                 = shift;
    my $does_pattern_match   = shift;
    my $argument_for_long_op = shift;
    my $is_repeat            = shift;

    my $ref = ref $usage_element;
    my $arg = shift @$args;
    $arg //= '';

    if (!$$does_pattern_match)
    {
        unshift @$args, $arg if $arg ne '';
        _undef_usage_element($usage_element, $result);
        return;
    }

    if ($usage_element->{is_repeat})
    {
        $usage_element->{is_repeat} = 0;
        unshift @$args, $arg if $arg ne '';
        my $matching = 1;
        my $whatever = 0;
        my $is_repeat = 1;
        while (@$args && $matching)
        {
            $matching = _handle_usage_element($usage_element, $result, $args, $does_pattern_match, \$whatever, $is_repeat);
            # exit 1;
        }
        return;
    }

    # -v, -vv, -czf, -etc
    if ($ref eq 'ShortOption')
    {
        say 'ShortOption';

        my $short_op = $usage_element->{name}; # without the '-'
        if ($arg =~ /^-\w/)
        {
            my $arg_copy = $arg;
            my $short_op_arg_letters = substr($arg, 1);

            my $short_op_letters_count = length $short_op;
            $arg = shift @$args;
            while (defined $arg && $arg =~ /^-\w/)
            {
                last if length($short_op_arg_letters) == $short_op_letters_count;
                $short_op_arg_letters .= substr($arg, 1);
                $arg = shift @$args;
            }
            unshift @$args, $arg if defined $arg;
            # say $short_op;
            # say $short_op_arg_letters;

            my @short_op_letters     = split //, $short_op;
            my @short_op_arg_letters = split //, $short_op_arg_letters;

            my $nothing_matches = 1;
            for my $short_op_letter (@short_op_letters)
            {
                for my $short_op_arg_letter (@short_op_arg_letters)
                {
                    if ($short_op_letter eq $short_op_arg_letter) { $result->{"-$short_op_letter"}++; $nothing_matches = 0; }
                    else
                    {
                        $result->{"-$short_op_letter"} //= undef;
                        if ($is_repeat)
                        {
                            $$does_pattern_match = 0;
                            return 0;
                        }
                    }
                }
            }
            # say "$short_op === $short_op_arg_letters";
            # say "\@short_op_letters: ", join('', sort @short_op_letters);
            # say join '', @short_op_arg_letters;
            # say "\@short_op_arg_letters: ", join('', sort @short_op_arg_letters);

            if ($nothing_matches) { unshift @$args, $arg_copy; };
            if ((join('', sort @short_op_letters) ne join('', sort @short_op_arg_letters)) && !$is_repeat)
            {
                $$does_pattern_match = 0;
            }
        }
        else
        {
            my @short_op_letters = split //, $short_op;
            for my $short_op_letter (@short_op_letters) { $result->{"-$short_op_letter"} = undef; }
            unshift @$args, $arg  if $arg ne '';

            $$does_pattern_match = 0;
        }
    }
    elsif ($ref eq 'Argument')
    {
        say 'Argument';

        my $arg_name    = $usage_element->{name};
        my $is_brackety = $usage_element->{is_brackety};

        if (!$argument_for_long_op)
        {
            if ($arg ne '' && $arg !~ /^-/)
            {
                if ($is_brackety)
                {
                    if (defined $result->{"<$arg_name>"})
                    {
                        $result->{"<$arg_name>"} = [ $result->{"<$arg_name>"} ] if ref $result->{"<$arg_name>"} ne 'ARRAY';
                        push @{ $result->{"<$arg_name>"} }, $arg;

                    }
                    else { $result->{"<$arg_name>"} = $arg; }
                }
                else
                {
                    if (defined $result->{$arg_name})
                    {
                        $result->{$arg_name} = [ $result->{$arg_name} ] if ref $result->{$arg_name} ne 'ARRAY';
                        push @{ $result->{$arg_name} }, $arg;
                    }
                    else { $result->{$arg_name} = $arg; }
                }

                return 1;
            }
            else
            {
                if ($is_brackety) { $result->{"<$arg_name>"} = undef; }
                else              { $result->{$arg_name}     = undef; }

                unshift @$args, $arg;
                $$does_pattern_match = 0;

                return 0;
            }
        }
        else
        {
            say 'is LongOption Argument';
            return $arg if $arg ne '';
            $$does_pattern_match = 0;
            return undef;
        }
    }
    elsif ($ref eq 'LongOption')
    {
        say 'LongOption';

        my $long_op = $usage_element->{name};
        # say "\$long_op: $long_op; \$arg: $arg";
        if ($arg =~ /^--$long_op/)
        {
            if ($usage_element->{argument})
            {
                if ($arg =~ /=/)
                {
                    $arg = (split /=/, $arg)[1];
                    unshift @$args, $arg;
                }

                if (defined $result->{"--$long_op"})
                {
                    $result->{"--$long_op"} = [ $result->{"--$long_op"} ] if ref $result->{"--$long_op"} ne 'ARRAY';
                    push @{ $result->{"--$long_op"} }, _handle_usage_element($usage_element->{argument}, $result, $args, $does_pattern_match, 1);
                }
                else
                {
                    $result->{"--$long_op"} = _handle_usage_element($usage_element->{argument}, $result, $args, $does_pattern_match, 1);
                }
            }
            else
            {
                $result->{"--$long_op"}++;
            }
         }
        else
        {
            $result->{"--$long_op"} = undef;
            if ($usage_element->{argument})
            {
                _undef_usage_element($usage_element->{argument}, $result);
            }

            unshift @$args, $arg if $arg ne '';
            $$does_pattern_match = 0;
        }
    }
    elsif ($ref eq 'ARRAY')
    {
        say 'ARRAY';
        unshift @$args, $arg if $arg ne '';
        for my $e (@{ $usage_element })
        {
            _handle_usage_element($e, $result, $args, $does_pattern_match);
        }
    }
    elsif ($ref eq 'Or')
    {
        say 'Or';
        unshift @$args, $arg if $arg ne '';

        my $or_list_elements_count = @{ $usage_element->{or_list} };
        my $failed_count = 0;
        my $or_matched = 0;
        for my $e (@{ $usage_element->{or_list} })
        {
            if ($or_matched)
            {
                # fail the rest
                _undef_usage_element($e, $result);
            }
            else
            {
                my $does_or_list_match = 1;
                _handle_usage_element($e, $result, $args, \$does_or_list_match);
                if ($does_or_list_match) { $or_matched = 1; }

                if ($does_or_list_match != 1) { $failed_count++; }
            }
        }
        # if no alternative matches
        if ($failed_count == $or_list_elements_count)
        {
            $$does_pattern_match = 0;
        }
    }
    elsif ($ref eq 'Optional')
    {
        say 'Optional';
        unshift @$args, $arg if $arg ne '';

        my $optional_match = 1;
        for my $e (@{ $usage_element->{usage_element_list} })
        {
            _handle_usage_element($e, $result, $args, \$optional_match);
        }
    }
    elsif ($ref eq 'Required')
    {
        say 'Required';
        unshift @$args, $arg if $arg ne '';

        for my $e (@{ $usage_element->{usage_element_list} })
        {
            _handle_usage_element($e, $result, $args, $does_pattern_match);
        }
    }
    else
    {
        say "can't handle '$ref' yet";
        $$does_pattern_match = 0;
        unshift @$args, $arg if $arg ne ''; # if we had an argument

        return 0;
    }

    return 1;
}

sub _undef_usage_element
{
    my $usage_element = shift;
    my $result        = shift;

    my $ref = ref $usage_element;

    if ($ref eq 'ShortOption')
    {
        say 'undef ShortOption';

        my $short_op = $usage_element->{name};
        for my $short_op_letter (split //, $short_op)
        {
            $result->{"-$short_op_letter"} //= undef;
        }
    }
    elsif ($ref eq 'Argument')
    {
        say 'undef Argument';

        my $arg_name    = $usage_element->{name};
        my $is_brackety = $usage_element->{is_brackety};
        if ($is_brackety) { $result->{"<$arg_name>"} //= undef; }
        else              { $result->{$arg_name}     //= undef; }
    }
    elsif ($ref eq 'LongOption')
    {
        my $long_op = $usage_element->{name};
        $result->{"--$long_op"} = undef;
        if ($usage_element->{argument}) { _undef_usage_element($usage_element->{argument}, $result); }
    }
    elsif ($ref eq 'ARRAY')
    {
        say 'undef ARRAY';

        for my $e (@{ $usage_element })
        {
            _undef_usage_element($e, $result);
        }
    }
    elsif ($ref eq 'Or')
    {
        say 'undef Or';

        for my $e (@{ $usage_element->{or_list} })
        {
            _undef_usage_element($e, $result);
        }
    }
    elsif ($ref eq 'Optional' || $ref eq 'Required')
    {
        say 'undef Optional' if $ref eq 'Optional';
        say 'undef Required' if $ref eq 'Required';

        for my $e (@{ $usage_element->{usage_element_list} })
        {
            _undef_usage_element($e, $result);
        }
    }
    else
    {
        say "can't undef '$ref' yet";
    }
}


    # script.pl [--version] [--exec-path=<path>] [--html-path]


    # counted_example.py (--path=<path>)...
    # calculator_example.py <value> ( ( + | - | * | / ) <value> )...

    # counted_example.pl (--path=<path>)...

    # script.pl <name> = <value>
    # calculator_example.pl <value> ( ( AA | BB | CC | DD ) <value> )...
    # calculator_example.pl <value> ( ( + | - | * | / ) <value> )...

    # script.pl git -o FILE
    # script.pl -o --
    # script.pl --list-of=A
    # script.pl --list-of=B


    # script.pl -a FILE
    # script.pl -o <FILY> FILE
    # script.pl -o FILE . --flag
    # hehe.pl --list-of
    # script.pl [ -o FILE ]
    # script.pl (A) | ((B))
    # script.pl -o (((FILE)))

    # script.pl <name> (<file> = <file>) ...
    # calculator_example.pl <value> ( ( + | - | * | / ) <value> )...
    #            <command> [<args>...]   # cal.pl (A | B) ...


    # arguments_example.pl [-vqrh] [FILE] ...
    # arguments_example.pl (--left | --right) CORRECTION FILE

    # counted_example.pl go [go]
    # calculator_example.pl <function> <value> [( , <value> )]...
    # calculator_example.pl (-h | --help)

    # naval_fate.pl ship new <name>...
    # naval_fate.pl ship <name> move <x> <y> [--speed=<kn>]
    # naval_fate.pl ship shoot <x> <y>
    # naval_fate.pl mine (set|remove) <x> <y> [--moored|--drifting]
    # naval_fate.pl --version

    # script.pl [--moored | --drifting]
    # calculator_example.pl <value> ( ( + | - | * | / ) <value> )...
    # naval_fate.pl -h | --help
    # script.pl [FILE ...]
    # script.pl <name> <value> -o
    # script.pl -o -a | -b
    # script.pl -a -o | -b
    # script.pl <file> <file>
    # script.pl FILE [ -o | <file> ] F2
    # script.pl -b
    # script.pl -a | -b
    # script.pl --lo1=<file> --lo2=FILE
    # script.pl (-o (-a | -b))
    # script.pl --long-op | -o
    # script.pl -a

    # script.pl [--version] [--exec-path=<path>] [--html-path]
    #             [ -p | --paginate | --no-pager ] [--no-replace-objects]
    #             [--bare] [--git-dir=<path>] [--work-tree=<path>]

    # quick_example.pl tcp <host> <port> [--timeout=<seconds>]
    # quick_example.pl serial <port> [--baud=9600] [--timeout=<seconds>]
    # quick_example.pl -h | --help | --version

    # script.pl <FILE> ...

__DATA__
Usage:
    script.pl --long-op=<file> ...


