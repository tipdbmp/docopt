package Docopt::Docopt;
our ($VERSION, @ISA, @EXPORT, @EXPORT_OK);
BEGIN
{
    require Exporter;
    $VERSION   = 1.00;
    @ISA       = qw|Exporter|;
    @EXPORT    = qw|docopt|;
    @EXPORT_OK = qw||;
}

use strict;
use warnings;
use v5.10;
use Parse::RecDescent;
use File::Slurp;
# use SectionsParser;
# use UsageParser;
# use Tie::IxHash;
use Encode;

use Cwd (); use File::Basename ();
my $__DIR__  = File::Basename::dirname(Cwd::abs_path(__FILE__));
require "$__DIR__/UsageParser.pm";
require "$__DIR__/SectionsParser.pm";

# if running as a script
if (!caller)
{
    $ENV{DOCOPT_DEBUG} = 1;

    my $docopt_string = join '', <DATA>;
    my $op = docopt($docopt_string, args => \@ARGV);

    say "\ndocopt returned: ";
    use DDP; p $op;
    # say '\ {';
    # for my $k (keys %$op)
    # {
    #     my $v = $op->{$k};
    #     $v = defined $v ? $v : 'undef';
    #     say ' ' x 4, "$k => '$v'";
    # }
    # say '}';
}

sub sayd { say @_ if $ENV{DOCOPT_DEBUG}; }

sub docopt
{
    my $docopt_string = shift;
    my %opt_args  = @_;
    my $args = $opt_args{args} // \@ARGV;

    my ($usage_string, $sections_string) = SectionsParser::get_usage_string_and_sections_string($docopt_string);

    # The user supplied pattern which we are going to compare to the usage patterns
    my $user_pattern_string = join ' ', @$args;
    $user_pattern_string    = decode('UTF-8', $user_pattern_string);
    $user_pattern_string    = "Usage:\n    script.pl $user_pattern_string";

    # sayd $usage_string;
    # sayd $sections_string;
    # sayd $user_pattern_string;
    # exit 1;

    my $usage = UsageParser::parse_usage($usage_string);

    my $sections = SectionsParser::parse_sections($sections_string);
    for my $section (@$sections)
    {
        for my $row (@{ $section->{rows} })
        {
            my $default_value = SectionsParser::extract_default_value_from_description($row->{option_description});
            $row->{default_value} = $default_value;
        }
    }

    my $user_pattern = UsageParser::parse_usage($user_pattern_string)->{usage_pattern_list}[0];

    use Data::Dumper; $Data::Dumper::Indent = 2; sayd Dumper($usage);
    use Data::Dumper; $Data::Dumper::Indent = 2; sayd Dumper($user_pattern);
    # use Data::Dumper; $Data::Dumper::Indent = 2; sayd Dumper($sections);
    # exit 1;

    my $docopt_result = {};
    # tie %$docopt_result, 'Tie::IxHash';

    my $a_pattern_matched = 0;
    for my $usage_pattern_index ( 0 .. @{ $usage->{usage_pattern_list} } - 1)
    {
        my $usage_pattern = $usage->{usage_pattern_list}[$usage_pattern_index];
        my $pattern_matched = _match_usage_pattern
        (
            usage_pattern => $usage_pattern,
            user_pattern  => $user_pattern,
            sections      => $sections,
            docopt_result => $docopt_result,
        );

        if ($pattern_matched)
        {
            # undef the rest of the patterns
            for my $usage_pattern_index2 ($usage_pattern_index + 1 .. @{ $usage->{usage_pattern_list} } - 1)
            {
                _undef_usage_pattern
                (
                    usage_pattern => $usage->{usage_pattern_list}[$usage_pattern_index2],
                    with_force    => 0,
                    docopt_result => $docopt_result,
                );
            }

            $a_pattern_matched = 1;

            # We are done
            # at
            last;
            # =)
        }
        else
        {
            sayd "pattern #$usage_pattern_index didn't match";
            _undef_usage_pattern
            (
                usage_pattern => $usage->{usage_pattern_list}[$usage_pattern_index],
                with_force    => 1,
                docopt_result => $docopt_result,
            );
        }
    }

    if ($a_pattern_matched)
    {
        sayd 'A pattern matched';

    }
    else
    {
        # say 'No pattern matched';
        if (!$ENV{DOCOPT_DEBUG})
        {
            print $docopt_string;
            exit 1;
        }
    }

    return $docopt_result;
}

sub _match_usage_pattern
{
    my $params = { @_ };
    my $usage_pattern = $params->{usage_pattern};
    my $user_pattern  = $params->{user_pattern};
    my $sections      = $params->{sections};
    my $docopt_result = $params->{docopt_result};

    my $user_pattern_element_index  = 0;
    for
    (
        my $usage_pattern_element_index = 0;
        $usage_pattern_element_index < @{ $usage_pattern->{usage_element_list} };
        $usage_pattern_element_index++
    )
    {
        my $usage_pattern_element = $usage_pattern->{usage_element_list}[$usage_pattern_element_index];
        my $user_pattern_element  = $user_pattern->{usage_element_list}[$user_pattern_element_index];

        my $matched = _try_match_elements
        (
            usage_pattern_element          =>  $usage_pattern_element,
            user_pattern_current_element   =>  $user_pattern_element,
            user_pattern_element_index_ref => \$user_pattern_element_index,
            user_pattern_element_list      =>  $user_pattern->{usage_element_list},
            sections                       =>  $sections,
            docopt_result                  =>  $docopt_result,
        );

        if (!$matched)
        {
            _undef_usage_element_list
            (
                usage_element_list => $usage_pattern->{usage_element_list},
                with_force         => 1,
                docopt_result      => $docopt_result,
            );
            return 0;
        }

        $user_pattern_element_index++ if $usage_pattern_element_index + 1 < @{ $usage_pattern->{usage_element_list} };
    }

    # say "\$user_pattern_element_index: $user_pattern_element_index";
    # say 0+@{ $user_pattern->{usage_element_list} };
    # return $user_pattern_element_index + 1 == @{ $user_pattern->{usage_element_list} };
    return 1;
}


sub _try_match_elements
{
    my $params = { @_ };

    my $usage_pattern_element          = $params->{usage_pattern_element};
    my $user_pattern_current_element   = $params->{user_pattern_current_element};
    my $user_pattern_element_index_ref = $params->{user_pattern_element_index_ref};
    my $user_pattern_element_list      = $params->{user_pattern_element_list};
    my $sections                       = $params->{sections};
    my $docopt_result                  = $params->{docopt_result};

    my $usage_pattern_element_type        = ref $usage_pattern_element;
    my $user_pattern_current_element_type = ref $user_pattern_current_element;

    if ($usage_pattern_element_type eq 'ShortOption' && $user_pattern_current_element_type eq 'ShortOption')
    {
        return _try_match_short_option
        (
            usage_pattern_element          => $usage_pattern_element,
            user_pattern_current_element   => $user_pattern_current_element,
            # user_pattern_element_index_ref => $user_pattern_element_index_ref,
            # user_pattern_element_list      => $user_pattern_element_list,
            sections                       => $sections,
            docopt_result                  => $docopt_result,
        ) if ! $usage_pattern_element->{is_repeat};

        my $at_least_once = 0;
        while
        (
            _try_match_short_option
            (
                usage_pattern_element          => $usage_pattern_element,
                user_pattern_current_element   => $user_pattern_current_element,
                # user_pattern_element_index_ref => $user_pattern_element_index_ref,
                # user_pattern_element_list      => $user_pattern_element_list,
                sections                       => $sections,
                docopt_result                  => $docopt_result,
            )
        )
        {
            $at_least_once++;
            $$user_pattern_element_index_ref++;
            $user_pattern_current_element = $user_pattern_element_list->[$$user_pattern_element_index_ref];
        }

        $$user_pattern_element_index_ref--;
        return $at_least_once > 0;
    }
    elsif ($usage_pattern_element_type eq 'LongOption' && $user_pattern_current_element_type eq 'LongOption')
    {
        return _try_match_long_option
        (
            usage_pattern_element          => $usage_pattern_element,
            user_pattern_current_element   => $user_pattern_current_element,
            user_pattern_element_index_ref => $user_pattern_element_index_ref,
            user_pattern_element_list      => $user_pattern_element_list,
            sections                       => $sections,
            docopt_result                  => $docopt_result,
        )
        if !$usage_pattern_element->{is_repeat};

        # If the long option's is_repeat flag is set:
        my $at_least_once = 0;
        while
        (
            my $res = _try_match_long_option
            (
                usage_pattern_element          => $usage_pattern_element,
                user_pattern_current_element   => $user_pattern_current_element,
                user_pattern_element_index_ref => $user_pattern_element_index_ref,
                user_pattern_element_list      => $user_pattern_element_list,
                sections                       => $sections,
                docopt_result                  => $docopt_result,
            )
        )
        {
            $at_least_once++;
            $$user_pattern_element_index_ref++;
            $user_pattern_current_element = $user_pattern_element_list->[$$user_pattern_element_index_ref];
        }

        $$user_pattern_element_index_ref--;
        return $at_least_once > 0;
    }
    elsif ($usage_pattern_element_type eq 'Argument' && ($user_pattern_current_element_type eq 'Argument' || $user_pattern_current_element_type eq 'Command'))
    {
        return _try_match_argument
        (
            usage_pattern_element        => $usage_pattern_element,
            user_pattern_current_element => $user_pattern_current_element,
            sections                     => $sections,
            docopt_result                => $docopt_result,
        ) if !$usage_pattern_element->{is_repeat};

        my $at_least_once = 0;
        while
        (
            _try_match_argument
            (
            usage_pattern_element        => $usage_pattern_element,
            user_pattern_current_element => $user_pattern_current_element,
            sections                     => $sections,
            docopt_result                => $docopt_result,
            )
        )
        {
            $at_least_once++;
            $$user_pattern_element_index_ref++;
            $user_pattern_current_element = $user_pattern_element_list->[$$user_pattern_element_index_ref];
        }

        $$user_pattern_element_index_ref--;
        return $at_least_once > 0;
    }
    elsif ($usage_pattern_element_type eq 'Command' && ($user_pattern_current_element_type eq 'Command' || $user_pattern_current_element_type eq 'Argument'))
    {
        return _try_match_command
        (
            usage_pattern_element        => $usage_pattern_element,
            user_pattern_current_element => $user_pattern_current_element,
            sections                     => $sections,
            docopt_result                => $docopt_result,
        ) if !$usage_pattern_element->{is_repeat};

        # makes no sense to repeat a command
        die '[docopt] error: commands are non-repeatable elements (', $usage_pattern_element->{name}, ')';
    }
    elsif ($usage_pattern_element_type eq 'Token' && $user_pattern_current_element_type eq 'Token')
    {
        return _try_match_token
        (
            usage_pattern_element        => $usage_pattern_element,
            user_pattern_current_element => $user_pattern_current_element,
            sections                     => $sections,
            docopt_result                => $docopt_result,
        );
    }
    elsif ($usage_pattern_element_type eq 'Optional')
    {
        return _try_match_optional
        (
            usage_pattern_element          => $usage_pattern_element,
            user_pattern_current_element   => $user_pattern_current_element,
            user_pattern_element_index_ref => $user_pattern_element_index_ref,
            user_pattern_element_list      => $user_pattern_element_list,
            sections                       => $sections,
            docopt_result                  => $docopt_result,
        ) if !$usage_pattern_element->{is_repeat};

        my $at_least_once = 0;
        my $old_user_pattern_element_index = $$user_pattern_element_index_ref;
        while
        (
            _try_match_optional
            (
                usage_pattern_element          => $usage_pattern_element,
                user_pattern_current_element   => $user_pattern_current_element,
                user_pattern_element_index_ref => $user_pattern_element_index_ref,
                user_pattern_element_list      => $user_pattern_element_list,
                sections                       => $sections,
                docopt_result                  => $docopt_result,
            )
        )
        {
            $at_least_once++;

            # break if no progress
            last if $old_user_pattern_element_index == $$user_pattern_element_index_ref;

            $$user_pattern_element_index_ref++;
            $user_pattern_current_element = $user_pattern_element_list->[$$user_pattern_element_index_ref];
            $old_user_pattern_element_index = $$user_pattern_element_index_ref;
        }

        return $at_least_once > 0;
    }
    elsif ($usage_pattern_element_type eq 'Required')
    {
        return _try_match_required
        (
            usage_pattern_element          => $usage_pattern_element,
            user_pattern_current_element   => $user_pattern_current_element,
            user_pattern_element_index_ref => $user_pattern_element_index_ref,
            user_pattern_element_list      => $user_pattern_element_list,
            sections                       => $sections,
            docopt_result                  => $docopt_result,
        ) if ! $usage_pattern_element->{is_repeat};

        my $at_least_once = 0;
        while
        (
            _try_match_required
            (
                usage_pattern_element          => $usage_pattern_element,
                user_pattern_current_element   => $user_pattern_current_element,
                user_pattern_element_index_ref => $user_pattern_element_index_ref,
                user_pattern_element_list      => $user_pattern_element_list,
                sections                       => $sections,
                docopt_result                  => $docopt_result,
            )
        )
        {
            $at_least_once++;
        }

        return $at_least_once > 0;
    }
    elsif ($usage_pattern_element_type eq 'ARRAY')
    {
        my $match_count = 0;
        for my $array_element (@{ $usage_pattern_element })
        {
            $match_count += _try_match_elements
            (
                usage_pattern_element          => $array_element,
                user_pattern_current_element   => $user_pattern_current_element,
                user_pattern_element_index_ref => $user_pattern_element_index_ref,
                user_pattern_element_list      => $user_pattern_element_list,
                sections                       => $sections,
                docopt_result                  => $docopt_result,
            );
            $$user_pattern_element_index_ref++;
            $user_pattern_current_element = $user_pattern_element_list->[$$user_pattern_element_index_ref];
        }

        return $match_count == 0+@{ $usage_pattern_element };
    }
    elsif ($usage_pattern_element_type eq 'Or')
    {
        # when an element get's matched the rest should be undef-ed

        for (my $i = 0; $i < @{ $usage_pattern_element->{usage_element_list} }; $i++)
        {
            if
            (
                _try_match_elements
                (
                    usage_pattern_element          => $usage_pattern_element->{usage_element_list}[$i],
                    user_pattern_current_element   => $user_pattern_current_element,
                    user_pattern_element_index_ref => $user_pattern_element_index_ref,
                    user_pattern_element_list      => $user_pattern_element_list,
                    sections                       => $sections,
                    docopt_result                  => $docopt_result,
                )
            )
            {
                for (my $j = $i + 1; $j < @{ $usage_pattern_element->{usage_element_list} }; $j++)
                {
                    _undef_usage_element
                    (
                        usage_element => $usage_pattern_element->{usage_element_list}[$j],
                        docopt_result => $docopt_result,
                    );
                }

                return 1;
            }
            else
            {
                _undef_usage_element
                (
                    usage_element => $usage_pattern_element->{usage_element_list}[$i],
                    docopt_result => $docopt_result,
                );
            }

        }
        return 0;
    }
    elsif ($usage_pattern_element_type eq 'SingleDash' && $user_pattern_current_element_type eq 'SingleDash')
    {
        _docopt_result_add_at
        (
            key           => '-',
            is_flag       => 1,
            docopt_result => $docopt_result,
        );
        return 1;
    }
    elsif ($usage_pattern_element_type eq 'DoubleDash' && $user_pattern_current_element_type eq 'DoubleDash')
    {
        _docopt_result_add_at
        (
            key           => '--',
            is_flag       => 1,
            docopt_result => $docopt_result,
        );
        return 1;
    }

    # say "usage: ", $usage_pattern_element->{name};
    # say "user:  ", $user_pattern_current_element->{name};

    return 0;
}

sub _try_match_short_option
{
    my $params = { @_ };

    my $usage_pattern_element          = $params->{usage_pattern_element};
    my $user_pattern_current_element   = $params->{user_pattern_current_element};
    # my $user_pattern_element_index_ref = $params->{user_pattern_element_index_ref};
    # my $user_pattern_element_list      = $params->{user_pattern_element_list};
    my $sections                       = $params->{sections};
    my $docopt_result                  = $params->{docopt_result};

    return 0 if !defined $user_pattern_current_element;

    # if (join('', sort(split //, $usage_pattern_element->{name}))  eq  join('', sort(split //, $user_pattern_current_element->{name})))
    # {
    #     for my $short_option_name (split //, $usage_pattern_element->{name})
    #     {
    #         _docopt_result_add_at
    #         (
    #             key           => "-$short_option_name",
    #             is_flag       => 1,
    #             docopt_result => $docopt_result,
    #         );
    #     }

    #     return 1;
    # }

    if ($usage_pattern_element->{name} eq $user_pattern_current_element->{name})
    {
        _docopt_result_add_at
        (
            key           => '-' . $usage_pattern_element->{name},
            is_flag       => 1,
            docopt_result => $docopt_result,
        );

        return 1;
    }

    return 0;
}

sub _try_match_long_option
{
    my $params = { @_ };

    my $usage_pattern_element          = $params->{usage_pattern_element};
    my $user_pattern_current_element   = $params->{user_pattern_current_element};
    my $user_pattern_element_index_ref = $params->{user_pattern_element_index_ref};
    my $user_pattern_element_list      = $params->{user_pattern_element_list};
    my $sections                       = $params->{sections};
    my $docopt_result                  = $params->{docopt_result};

    return 0 if !defined $user_pattern_current_element;
    return 0 if $usage_pattern_element->{name} ne $user_pattern_current_element->{name};

    if (defined $usage_pattern_element->{argument})
    {
        if (!defined $user_pattern_current_element->{argument})
        {
            $$user_pattern_element_index_ref++; return 0 if !defined $user_pattern_element_list->[$$user_pattern_element_index_ref];
            my $user_pattern_next_element = $user_pattern_element_list->[$$user_pattern_element_index_ref];
            my $user_pattern_next_element_type = ref $user_pattern_next_element;
            if ($user_pattern_next_element_type eq 'Token')
            {
                return 0 if $user_pattern_next_element->{name} ne '=';
                $$user_pattern_element_index_ref++; return 0 if !defined $user_pattern_element_list->[$$user_pattern_element_index_ref];
                $user_pattern_next_element = $user_pattern_element_list->[$$user_pattern_element_index_ref];
                my $user_pattern_next_element_type = ref $user_pattern_next_element;

                return 0 if $user_pattern_next_element_type ne 'Command' && $user_pattern_next_element_type ne 'Argument';

                _docopt_result_add_at
                (
                    key           => $usage_pattern_element->{name},
                    value         => $user_pattern_next_element->{name},
                    docopt_result => $docopt_result,
                );
            }
            elsif ($user_pattern_next_element_type eq 'Command' || $user_pattern_next_element_type eq 'Argument')
            {
                _docopt_result_add_at
                (
                    key           => $usage_pattern_element->{name},
                    value         => $user_pattern_next_element->{name},
                    docopt_result => $docopt_result,
                );
            }
            else
            {
                return 0;
            }
        }
        else
        {
            _docopt_result_add_at
            (
                key           => $usage_pattern_element->{name},
                value         => $user_pattern_current_element->{argument}{name},
                docopt_result => $docopt_result,
            );

        }
    }
    else
    {
        _docopt_result_add_at
        (
            key           => $usage_pattern_element->{name},
            # value         => 1,
            is_flag       => 1,
            docopt_result => $docopt_result,
        );
    }


    return 1;
}

sub _try_match_argument
{
    my $params = { @_ };

    my $usage_pattern_element        = $params->{usage_pattern_element};
    my $user_pattern_current_element = $params->{user_pattern_current_element};
    my $sections                     = $params->{sections};
    my $docopt_result                = $params->{docopt_result};

    return 0 if !defined $user_pattern_current_element;
    return 0 if $user_pattern_current_element->{name} =~ /^-/;

    my $key = $usage_pattern_element->{name};
    if ($usage_pattern_element->{is_brackety})
    {
        $key = "<$key>";
    }
    _docopt_result_add_at
    (
        key           => $key,
        value         => $user_pattern_current_element->{name},
        docopt_result => $docopt_result,
    );

    return 1;
}

sub _try_match_command
{
    my $params = { @_ };

    my $usage_pattern_element        = $params->{usage_pattern_element};
    my $user_pattern_current_element = $params->{user_pattern_current_element};
    my $sections                     = $params->{sections};
    my $docopt_result                = $params->{docopt_result};

    return 0 if !defined $user_pattern_current_element;
    return 0 if $user_pattern_current_element->{name} =~ /^-/;

    if ($usage_pattern_element->{name} eq $user_pattern_current_element->{name})
    {
        _docopt_result_add_at
        (
            key           => $usage_pattern_element->{name},
            is_flag       => 1,
            docopt_result => $docopt_result,
        );
        return 1;
    }
}

sub _try_match_token
{
    my $params = { @_ };

    my $usage_pattern_element        = $params->{usage_pattern_element};
    my $user_pattern_current_element = $params->{user_pattern_current_element};
    my $sections                     = $params->{sections};
    my $docopt_result                = $params->{docopt_result};

    return 0 if !defined $user_pattern_current_element;
    return 0 if $usage_pattern_element->{name} ne $user_pattern_current_element->{name};
    _docopt_result_add_at
    (
        key           => $usage_pattern_element->{name},
        is_flag       => 1,
        docopt_result => $docopt_result,
    );

    return 1;
}

sub _try_match_optional
{
    my $params = { @_ };

    my $usage_pattern_element          = $params->{usage_pattern_element};
    my $user_pattern_current_element   = $params->{user_pattern_current_element};
    my $user_pattern_element_index_ref = $params->{user_pattern_element_index_ref};
    my $user_pattern_element_list      = $params->{user_pattern_element_list};
    my $sections                       = $params->{sections};
    my $docopt_result                  = $params->{docopt_result};

    # empty optional list, i.e [] is always matched
    return 1 if @{ $usage_pattern_element->{usage_element_list} } == 0;


    my @matching_usage_elements;

    # if the first element in the optional list matches, all the others must also match
    my $first_matched = _try_match_elements
    (
        usage_pattern_element          => $usage_pattern_element->{usage_element_list}[0],
        user_pattern_current_element   => $user_pattern_current_element,
        user_pattern_element_index_ref => $user_pattern_element_index_ref,
        user_pattern_element_list      => $user_pattern_element_list,
        sections                       => $sections,
        docopt_result                  => $docopt_result,
    );

    push @matching_usage_elements, $usage_pattern_element->{usage_element_list}[0] if $first_matched;

    if ($first_matched)
    {
        my $match_count = 0;
        for (my $i = 1; $i < @{ $usage_pattern_element->{usage_element_list} }; $i++)
        {
            $$user_pattern_element_index_ref++;
            $user_pattern_current_element = $user_pattern_element_list->[$$user_pattern_element_index_ref];

            my $matched = _try_match_elements
            (
                usage_pattern_element          => $usage_pattern_element->{usage_element_list}[$i],
                user_pattern_current_element   => $user_pattern_current_element,
                user_pattern_element_index_ref => $user_pattern_element_index_ref,
                user_pattern_element_list      => $user_pattern_element_list,
                sections                       => $sections,
                docopt_result                  => $docopt_result,
            );
            $match_count += $matched;

            if ($matched)
            {
                push @matching_usage_elements, $usage_pattern_element->{usage_element_list}[$i];
            }
        }
        # say "\$match_count: $match_count";

        if ($match_count != @{ $usage_pattern_element->{usage_element_list} } - 1)
        {
            # say 'Doo: ', 0+@matching_usage_elements;
            # say '!', $_->{name}, '!' for @matching_usage_elements;
            # say "A: $match_count";
            for my $usage_pattern_element (@matching_usage_elements)
            {
                my $type = ref $usage_pattern_element;
                if ($type eq 'LongOption' || $type eq 'Command' || $type eq 'Argument')
                {
                    my $is_flag = ! (($type eq 'LongOption' && defined $usage_pattern_element->{argument}) || $type eq 'Command' || $type eq 'Argument');
                    _docopt_result_sub_at
                    (
                        key           => $usage_pattern_element->{name},
                        is_flag       => $is_flag,
                        docopt_result => $docopt_result,
                    );
                }
            }
        }

        # say "\$match_count: $match_count";
        # say @{ $usage_pattern_element->{usage_element_list} } - 1;
        return $match_count == @{ $usage_pattern_element->{usage_element_list} } - 1;
    }
    # if the first doesn't match, undef all the elements, and return 1
    else
    {
        _undef_usage_element_list(usage_element_list => $usage_pattern_element->{usage_element_list}, docopt_result => $docopt_result);
        # say 'AAA';
        return 1;
    }
}

sub _try_match_required
{
    my $params = { @_ };

    my $usage_pattern_element          = $params->{usage_pattern_element};
    my $user_pattern_current_element   = $params->{user_pattern_current_element};
    my $user_pattern_element_index_ref = $params->{user_pattern_element_index_ref};
    my $user_pattern_element_list      = $params->{user_pattern_element_list};
    my $sections                       = $params->{sections};
    my $docopt_result                  = $params->{docopt_result};

    # empty required list, i.e () is always matched
    return 1 if @{ $usage_pattern_element->{usage_element_list} } == 0;

    my $match_count = 0;
    for my $required_element (@{ $usage_pattern_element->{usage_element_list} })
    {
        $match_count += _try_match_elements
        (
            usage_pattern_element          => $required_element,
            user_pattern_current_element   => $user_pattern_current_element,
            user_pattern_element_index_ref => $user_pattern_element_index_ref,
            user_pattern_element_list      => $user_pattern_element_list,
            sections                       => $sections,
            docopt_result                  => $docopt_result,
        );
        $$user_pattern_element_index_ref++;
        $user_pattern_current_element = $user_pattern_element_list->[$$user_pattern_element_index_ref];
    }

    return $match_count == 0+@{ $usage_pattern_element->{usage_element_list} };
}

sub _docopt_result_add_at
{
    my $params = { @_ };

    if ($params->{is_flag})
    {
        $params->{docopt_result}{$params->{key}}++;
    }
    else
    {
        if (!exists $params->{docopt_result}{$params->{key}})
        {
            $params->{docopt_result}{$params->{key}} = $params->{value};
        }
        elsif (ref $params->{docopt_result}{$params->{key}} eq 'ARRAY')
        {
            push @{ $params->{docopt_result}{$params->{key}} }, $params->{value};
        }
        else
        {
            $params->{docopt_result}{$params->{key}} = [ $params->{docopt_result}{$params->{key}}, $params->{value} ];
        }
    }
}

sub _docopt_result_sub_at
{
    my $params = { @_ };

    my $key           = $params->{key};
    my $is_flag       = $params->{is_flag};
    my $docopt_result = $params->{docopt_result};

    if ($is_flag)
    {
        if (defined $docopt_result->{$key})
        {
            $docopt_result->{$key}--;
        }
    }
    else
    {
        if (defined $docopt_result->{$key})
        {
            if (ref $docopt_result->{$key} eq 'ARRAY')
            {
                pop @{ $docopt_result->{$key} };
            }
            else
            {
                $docopt_result->{$key} = undef;
            }
        }
    }
}

sub _undef_usage_pattern
{
    my $params = { @_ };

    _undef_usage_element_list
    (
        usage_element_list => $params->{usage_pattern}{usage_element_list},
        with_force         => $params->{with_force},
        docopt_result      => $params->{docopt_result},
    );
}

sub _undef_usage_element_list
{
    my $params = { @_ };

    for my $element (@{ $params->{usage_element_list} })
    {
        _undef_usage_element
        (
            usage_element => $element,
            with_force    => $params->{with_force},
            docopt_result => $params->{docopt_result},
        );
    }
}

sub _undef_usage_element
{
    my $params        = { @_ };
    my $element       = $params->{usage_element};
    my $with_force    = $params->{with_force};
    my $docopt_result = $params->{docopt_result};

    my $element_type = ref $element;

    if ($element_type eq 'Or' || $element_type eq 'Required' || $element_type eq 'Optional')
    {
        for my $e (@{ $element->{usage_element_list} })
        {
            _undef_usage_element(usage_element => $e, with_force => $params->{with_force}, docopt_result => $docopt_result);
        }
    }
    elsif ($element_type eq 'ARRAY')
    {
        for my $e (@{ $element })
        {
            _undef_usage_element(usage_element => $e, with_force => $params->{with_force}, docopt_result => $docopt_result);
        }
    }
    elsif ($element_type eq 'ShortOption')
    {
        for my $short_option_name (split //, $element->{name})
        {
            $docopt_result->{"-$short_option_name"} = undef;
        }
    }
    else
    {
        my $element_name = $element->{name};
        if ($element->{is_brackety})
        {
            $element_name = "<$element_name>";
        }

        if ($with_force)
        {
            $docopt_result->{ $element_name } = undef;
        }
        else
        {
            $docopt_result->{ $element_name } = undef if !exists $docopt_result->{ $element_name };
        }
    }
}

1;


__DATA__
Usage:
    testcases.pl -h | --help
    testcases.pl [ (-s | --show) <test_number> ]
    testcases.pl run

Options:
    -o, --open  Sections don't currently work. [default: 1234]

Advanced Options:
    --whatever  Ignore this.
