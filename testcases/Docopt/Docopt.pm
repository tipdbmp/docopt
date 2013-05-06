package Docopt::Docopt; # o.O

our ($VERSION, @ISA, @EXPORT, @EXPORT_OK);
BEGIN
{
    require Exporter;
    $VERSION   = 1.00;
    @ISA       = qw|Exporter|;
    @EXPORT    = qw||;
    @EXPORT_OK = qw|docopt|;
}

use strict;
use warnings;
use v5.10;
use Parse::RecDescent;
use File::Slurp;

use Cwd (); use File::Basename ();
my $__DIR__  = File::Basename::dirname(Cwd::abs_path(__FILE__));
# my $__NAME__ = File::Basename::basename(__FILE__) =~ s/\.pm$//r;


my $skip_spaces_and_comments = qr{
    (?mxs:
        \s+     # skip whitespace including \n
      | \# .*?$ # skip line comments
    )*
}x;
$Parse::RecDescent::skip = $skip_spaces_and_comments;
my $grammar = read_file("$__DIR__/docopt.grammar");
my $parser = new Parse::RecDescent($grammar);
say '[docopt] error in grammar' and exit 1 if !$parser;


sub docopt
{
    my $docopt_string = shift;
    my %opt_args  = @_;
    my $args = $opt_args{args} // \@ARGV;


    # print "|$docopt_string|";
    # say "\n------------";
    my ($usage_section_str) = $docopt_string =~ /(usage:(.|\n)+?\n\n)/i;
    if (!defined $usage_section_str)
    {
        ($usage_section_str) = $docopt_string =~ /^(usage:.+)$/;
        if (!defined $usage_section_str)
        {
            die '"usage: ..." section not found';
        }
    }
    # print "|$usage_section_str|"; exit 1;


    my $t = $parser->parse($usage_section_str);
    die '[docopt] error: could not parse the usage section' if !defined $t;

    # use Data::Dumper; $Data::Dumper::Indent = 2; say Dumper($t); exit 1;

    # say $usage_section_str;
    # say '@ARGV: [', join(', ', @$args), ']', "\n";

    my $usage_section = $t;
    # say ref $usage_section;

    my $result = {};
    my $does_pattern_match;
    my @args_copy;
    my $fail_the_rest = 0;
    my $at_least_one_match = 0;
    for my $usage_pattern (@{ $usage_section->{usage_pattern_list} })
    {
        if ($fail_the_rest)
        {
            _undef_usage_pattern($usage_pattern, $result, 0);
            next;
        }

        @args_copy = @$args;

        $does_pattern_match = 1;
        _handle_usage_pattern($usage_pattern, $result, \@args_copy, \$does_pattern_match);
        if ($does_pattern_match)
        {
            $fail_the_rest = 1;
            $at_least_one_match = 1;
        }
        else
        {
            _undef_usage_pattern($usage_pattern, $result, 1);
        }
    }

    # if there are arguments left, fail
    if (@args_copy)
    {
        # say 'unused arguments:'; use DDP; p @args_copy;
        $at_least_one_match = 0;
    }

    if ($at_least_one_match)
    {
        # say "\nOkay, a pattern matched";
    }
    else
    {
        # say "\nShould probably show the usage string";
        die q|"user-error"|;
    }

    return $result;
}

sub _handle_usage_pattern
{
    my $usage_pattern      = shift;
    my $result             = shift;
    my $args               = shift;
    my $does_pattern_match = shift;

    my $usage_element_list = $usage_pattern->{usage_element_list};
    _simplify_usage_element_list($usage_element_list);
    # use Data::Dumper; $Data::Dumper::Indent = 2; say Dumper($usage_pattern);
    # exit 1;
    for my $usage_element (@{ $usage_element_list })
    {
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
    my $usage_element           = shift;
    my $result                  = shift;
    my $args                    = shift;
    my $does_pattern_match      = shift;
    my $is_argument_for_long_op = shift;
    my $is_repeat               = shift;

    my $ref = ref $usage_element;
    my $arg = shift @$args;
    $arg //= '';
    # say "\$ref => |$ref|; \$arg => !$arg!";
    # say '$is_repeat: ', $is_repeat ? 1 : 0;

    # FILE ...
    if ($ref ne 'ARRAY' && $usage_element->{is_repeat})
    {
        # say "$ref is repeating";

        unshift @$args, $arg if $arg ne '';
        if (!@$args)
        {
            # say 'no arguments, yet usage has ...';
            _undef_usage_element($usage_element, $result, 1);
            return $$does_pattern_match = 0;
        }

        $usage_element->{is_repeat} = 0;
        my $is_argument_for_long_op = 0;
        my $is_repeat = 1;
        my $matching = 1;
        while (@$args && $matching)
        {
            $matching = _handle_usage_element($usage_element, $result, $args, $does_pattern_match,
                                              $is_argument_for_long_op, $is_repeat);
        }
        return 1;
    }

    # -v, -vv, -czf, -etc
    if ($ref eq 'ShortOption')
    {
        # say 'ShortOption';

        if ($arg =~ /^-\w/)
        {
            my $short_op_letters     = $usage_element->{name}; # without the '-'
            my $short_op_arg_letters = '';

            my $short_op_letters_count = length($short_op_letters);
            my @slurped_args;
            while (defined $arg && $arg =~ /^-\w/ && length($short_op_arg_letters) < $short_op_letters_count)
            {
                push @slurped_args, $arg;
                $short_op_arg_letters .= substr($arg, 1);
                $arg = shift @$args;
            }
            unshift @$args, $arg if defined $arg;

            # say "\$short_op: $short_op_letters; \$short_op_arg_letters: $short_op_arg_letters";
            # say "\$args: "; use DDP; p $args;

            if (length $short_op_letters != length $short_op_arg_letters)
            {
                # say 'length $short_op != length $short_op_arg_letters';
                if (@slurped_args)
                {
                    unshift @$args, @slurped_args;
                }
                else
                {
                    # say 'KABOOM';
                    unshift @$args, $arg if $arg ne '';
                }
                # say 'WHATEVER';
                _undef_usage_element($usage_element, $result, 1);
                return $$does_pattern_match = 0;
            }

            my @short_op_letters     = sort split //, $short_op_letters;
            my @short_op_arg_letters = sort split //, $short_op_arg_letters;

            for my $i (0 .. $#short_op_letters)
            {
                my $short_op_letter     = $short_op_letters[$i];
                my $short_op_arg_letter = $short_op_arg_letters[$i];
                if ($short_op_letter eq $short_op_arg_letter)
                {
                    $result->{"-$short_op_letter"}++;
                }
                else
                {
                    unshift @$args, @slurped_args;
                    _undef_usage_element($usage_element, $result, 1);
                    return $$does_pattern_match = 0;
                }
            }
        }
        else
        {
            # say "ShortOption failed: \$arg: '$arg'";
            unshift @$args, $arg if $arg ne '';
            _undef_usage_element($usage_element, $result, 1);
            return $$does_pattern_match = 0;
        }
    }
    # FILE, <file>
    elsif ($ref eq 'Argument')
    {
        # say 'Argument';

        my $arg_name    = $usage_element->{name};
        my $is_brackety = $usage_element->{is_brackety};

        if (!$is_argument_for_long_op)
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
                    else
                    {
                        if ($is_repeat)
                        {
                            $result->{"<$arg_name>"} = [ $arg ];
                        }
                        else
                        {
                            $result->{"<$arg_name>"} = $arg;
                        }
                    }
                }
                else
                {
                    if (defined $result->{$arg_name})
                    {
                        $result->{$arg_name} = [ $result->{$arg_name} ] if ref $result->{$arg_name} ne 'ARRAY';
                        push @{ $result->{$arg_name} }, $arg;
                    }
                    else
                    {
                        if ($is_repeat)
                        {
                            $result->{$arg_name} = [ $arg ];
                        }
                        else
                        {
                            $result->{$arg_name} = $arg;
                        }
                    }
                }
            }
            else
            {
                _undef_usage_element($usage_element, $result, 1);
                return $$does_pattern_match = 0;
            }
        }
        else
        {
            # say 'is LongOption Argument';
            return $arg if $arg ne '';
            _undef_usage_element($usage_element, $result, 1);
            $$does_pattern_match = 0;
            return undef;
        }
    }
    # --long-option, --long-option-with-argument=<arg>
    elsif ($ref eq 'LongOption')
    {
        # say 'LongOption';

        my $long_op = $usage_element->{name};
        # say "\$long_op: $long_op; \$arg: |$arg|";
        if ($arg =~ /^--$long_op/)
        {
            if ($usage_element->{argument})
            {
                if ($arg =~ /=/)
                {
                    $arg = (split /=/, $arg)[1];
                    unshift @$args, $arg;
                }

                my $is_argument_for_long_op = 1;
                if (defined $result->{"--$long_op"})
                {
                    $result->{"--$long_op"} = [ $result->{"--$long_op"} ] if ref $result->{"--$long_op"} ne 'ARRAY';
                    push @{ $result->{"--$long_op"} },
                        _handle_usage_element($usage_element->{argument},
                                              $result, $args, $does_pattern_match, $is_argument_for_long_op);
                }
                else
                {
                    $result->{"--$long_op"} =
                        _handle_usage_element($usage_element->{argument},
                                              $result, $args, $does_pattern_match, $is_argument_for_long_op);
                }
            }
            else
            {
                $result->{"--$long_op"}++;
            }
         }
        else
        {
            unshift @$args, $arg if $arg ne '';
            _undef_usage_element($usage_element, $result, 1);
            return $$does_pattern_match = 0;
        }
    }
    elsif ($ref eq 'ARRAY')
    {
        # say 'ARRAY';

        unshift @$args, $arg if $arg ne '';
        for my $e (@{ $usage_element })
        {
            _handle_usage_element($e, $result, $args, $does_pattern_match);
        }
    }
    # -h | --help
    elsif ($ref eq 'Or')
    {
        # say 'Or';

        unshift @$args, $arg if $arg ne '';
        my $or_list_elements_count = @{ $usage_element->{or_list} };
        my $failed_count = 0;
        my $or_matched   = 0;
        for my $e (@{ $usage_element->{or_list} })
        {
            if ($or_matched)
            {
                # fail the rest
                _undef_usage_element($e, $result, 0);
                next;
            }

            my $does_or_list_match = 1;
            _handle_usage_element($e, $result, $args, \$does_or_list_match);
            if ( $does_or_list_match) { $or_matched = 1; }
            if (!$does_or_list_match) { $failed_count++; }
        }
        # if no alternative matches
        if ($failed_count == $or_list_elements_count)
        {
            $$does_pattern_match = 0;
            _undef_usage_element($usage_element, $result, 1);
            return 0;
        }
    }
    # [ --verbose ]
    elsif ($ref eq 'Optional')
    {
        # say 'Optional';

        unshift @$args, $arg if $arg ne '';
        my $optional_match = 1;
        for my $e (@{ $usage_element->{usage_element_list} })
        {
            if ($$does_pattern_match)
            {
                _handle_usage_element($e, $result, $args, \$optional_match);
            }
            else
            {
                _undef_usage_element($e, $result, 1);
            }
        }
    }
    # -o (FILE), same as -o FILE
    elsif ($ref eq 'Required')
    {
        # say 'Required';

        unshift @$args, $arg if $arg ne '';
        for my $e (@{ $usage_element->{usage_element_list} })
        {
            _handle_usage_element($e, $result, $args, $does_pattern_match);
        }
    }
    # git, add
    elsif ($ref eq 'Command')
    {
        # say 'Command';

        # if ($arg =~ /^[.\w]{2,}$/ && $arg eq )
        if ($arg eq $usage_element->{name})
        {
            # argument seems to be a valid command
            $result->{ $usage_element->{name} } = 1;
        }
        else
        {
            # say "didn't match command ", $usage_element->{name};
            unshift @$args, $arg if $arg ne '';
            _undef_usage_element($usage_element, $result, 1);
            $$does_pattern_match = 0;
            return 0;
        }
    }
    elsif ($ref eq 'Token')
    {
        # say 'Token';
        # say 'Token: $arg is |', $arg, '| expected ', '|', $usage_element->{token}, '|';

        if ($arg eq $usage_element->{token})
        {
            $result->{ $usage_element->{token} }++;
        }
        else
        {
            unshift @$args, $arg if $arg ne '';
            _undef_usage_element($usage_element, $result, 0);
            return $$does_pattern_match = 0;
        }
    }
    elsif ($ref eq 'SingleDash')
    {
        # say 'SingleDash';

        if ($arg eq '-')
        {
            $result->{'-'}++;
        }
        else
        {
            unshift @$args, $arg if $arg ne '';
            _undef_usage_element($usage_element, $result, 0);
            return $$does_pattern_match = 0;
        }
    }
    elsif ($ref eq 'DoubleDash')
    {
        # say 'DoubleDash';

        if ($arg eq '--')
        {
            # There can only be one of those?
            $result->{'--'} = 1;
        }
        else
        {
            unshift @$args, $arg if $arg ne '';
            _undef_usage_element($usage_element, $result, 0);
            return $$does_pattern_match = 0;
        }
    }
    else
    {
        # say "can't handle '$ref' yet";
        die "can't handle '$ref' yet";

        unshift @$args, $arg if $arg ne ''; # if we had an argument
        $$does_pattern_match = 0;
        return 0;
    }

    return 1;
}

sub _undef_usage_pattern
{
    my $usage_pattern      = shift;
    my $result             = shift;
    my $with_force         = shift;

    for my $usage_element(@{ $usage_pattern->{usage_element_list} })
    {
        _undef_usage_element($usage_element, $result, $with_force);
    }
}

sub _undef_usage_element
{
    my $usage_element = shift;
    my $result        = shift;
    my $with_force    = shift;

    # say $with_force ? '$with_force: 1' : '$with_force: 0';

    my $ref = ref $usage_element;

    if ($ref eq 'ShortOption')
    {
        # say 'undef ShortOption';

        my $short_op = $usage_element->{name};
        for my $short_op_letter (split //, $short_op)
        {
            if ($with_force) { $result->{"-$short_op_letter"}   = undef; }
            else             { $result->{"-$short_op_letter"} //= undef; }
            # $result->{"-$short_op_letter"} //= undef;
        }
    }
    elsif ($ref eq 'Argument')
    {
        # say 'undef Argument';

        my $arg_name    = $usage_element->{name};
        my $is_brackety = $usage_element->{is_brackety};

        if ($with_force)
        {
            if ($is_brackety) { $result->{"<$arg_name>"} = undef; }
            else              { $result->{$arg_name}     = undef; }
        }
        else
        {
            if ($is_brackety) { $result->{"<$arg_name>"} //= undef; }
            else              { $result->{$arg_name}     //= undef; }
        }
            # if ($is_brackety) { $result->{"<$arg_name>"} //= undef; }
            # else              { $result->{$arg_name}     //= undef; }
    }
    elsif ($ref eq 'LongOption')
    {
        # say 'undef LongOption';

        my $long_op = $usage_element->{name};
        if ($with_force) { $result->{"--$long_op"}   = undef; }
        else             { $result->{"--$long_op"} //= undef; }
        # $result->{"--$long_op"} //= undef;
        # if ($usage_element->{argument}) { _undef_usage_element($usage_element->{argument}, $result); }
    }
    elsif ($ref eq 'ARRAY')
    {
        # say 'undef ARRAY';

        for my $e (@{ $usage_element })
        {
            _undef_usage_element($e, $result, $with_force);
        }
    }
    elsif ($ref eq 'Or')
    {
        # say 'undef Or';

        for my $e (@{ $usage_element->{or_list} })
        {
            _undef_usage_element($e, $result, $with_force);
        }
    }
    elsif ($ref eq 'Optional' || $ref eq 'Required')
    {
        # say 'undef Optional' if $ref eq 'Optional';
        # say 'undef Required' if $ref eq 'Required';

        for my $e (@{ $usage_element->{usage_element_list} })
        {
            _undef_usage_element($e, $result, $with_force);
        }
    }
    elsif ($ref eq 'Command')
    {
        # say 'undef Command';

        if ($with_force) { $result->{ $usage_element->{name} }   = undef; }
        else             { $result->{ $usage_element->{name} } //= undef; }
    }
    elsif ($ref eq 'Token')
    {
        # say 'undef Token';

        if ($with_force) { $result->{ $usage_element->{token} }   = undef; }
        else             { $result->{ $usage_element->{token} } //= undef; }
    }
    elsif ($ref eq 'SingleDash')
    {
        # say 'undef SingleDash';

        if ($with_force) { $result->{'-'}   = undef; }
        else             { $result->{'-'} //= undef; }
    }
    elsif ($ref eq 'DoubleDash')
    {
        # say 'undef DoubleDash';

        if ($with_force) { $result->{'--'}   = undef; }
        else             { $result->{'--'} //= undef; }
    }
    else
    {
        # say "can't undef '$ref' yet";
    }
}

1;
