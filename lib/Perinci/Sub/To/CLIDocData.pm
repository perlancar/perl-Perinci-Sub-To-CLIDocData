package Perinci::Sub::To::CLIDocData;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;

use Perinci::Object;
use Perinci::Sub::Util qw(err);

our %SPEC;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(gen_cli_doc_data_from_meta);

sub _has_cats {
    for my $spec (@{ $_[0] }) {
        for (@{ $spec->{tags} // [] }) {
            my $tag_name = ref($_) ? $_->{name} : $_;
            if ($tag_name =~ /^category:/) {
                return 1;
            }
        }
    }
    0;
}

sub _add_category_from_spec {
    my ($cats_spec, $thing, $spec, $noun, $has_cats) = @_;
    my @cats;
    for (@{ $spec->{tags} // [] }) {
        my $tag_name = ref($_) ? $_->{name} : $_;
        if ($tag_name =~ /^category(\d+)?:(.+)/) {
            my $cat = ucfirst($2);
            my $ordering = $1 // 50;
            $cat =~ s/-/ /g;
            $cat .= " " . $noun;
            push @cats, [$cat, $ordering]; # name, ordering
        }
    }
    if (!@cats) {
        @cats = [$has_cats ? "Other $noun" : ucfirst($noun), 99]; # XXX translatable?
    }

    # old, will be removed someday
    $thing->{category} = $cats[0][0];
    # new/current
    $thing->{categories} = [map {$_->[0]} @cats];

    $cats_spec->{$_->[0]}{order} //= $_->[1] for @cats;
}

sub _add_default_from_arg_spec {
    my ($opt, $arg_spec) = @_;
    if (exists $arg_spec->{default}) {
        $opt->{default} = $arg_spec->{default};
    } elsif ($arg_spec->{schema} && exists($arg_spec->{schema}[1]{default})) {
        $opt->{default} = $arg_spec->{schema}[1]{default};
    }
}

sub _dash_prefix {
    length($_[0]) > 1 ? "--$_[0]" : "-$_[0]";
}

sub _fmt_opt {
    my $spec = shift;
    my @ospecs = @_;
    my @res;
    my $i = 0;
    for my $ospec (@ospecs) {
        my $j = 0;
        my $parsed = $ospec->{parsed};
        for (@{ $parsed->{opts} }) {
            my $opt = _dash_prefix($_);
            if ($i==0 && $j==0) {
                if ($parsed->{type}) {
                    if ($spec->{'x.schema.entity'}) {
                        $opt .= "=".$spec->{'x.schema.entity'};
                    } elsif ($spec->{'x.schema.element_entity'}) {
                        $opt .= "=".$spec->{'x.schema.element_entity'};
                    } else {
                        $opt .= "=$parsed->{type}";
                    }
                }
                # mark required option with a '*'
                $opt .= "*" if $spec->{req} && !$ospec->{is_base64} &&
                    !$ospec->{is_json} && !$ospec->{is_yaml};
            }
            push @res, $opt;
            $j++;
        }
        $i++;
    }
    join ", ", @res;
}

$SPEC{gen_cli_doc_data_from_meta} = {
    v => 1.1,
    summary => 'From Rinci function metadata, generate structure convenient '.
        'for producing CLI documentation (help/usage/POD)',
    description => <<'_',

This function calls <pm:Perinci::Sub::GetArgs::Argv>'s
`gen_getopt_long_spec_from_meta()` (or receive its result as an argument, if
passed, to avoid calling the function twice) and post-processes it: produce
command usage line, format the options, include information from metadata, group
the options by category. It also selects examples in the `examples` property
which are applicable to CLI environment and format them.

The resulting data structure is convenient to use when one wants to produce a
documentation for CLI program (including help/usage message and POD).

_
    args => {
        meta => {
            schema => 'hash*', # XXX rifunc
            req => 1,
            pos => 0,
        },
        meta_is_normalized => {
            schema => 'bool*',
        },
        common_opts => {
            summary => 'Will be passed to gen_getopt_long_spec_from_meta()',
            schema  => 'hash*',
        },
        ggls_res => {
            summary => 'Full result from gen_getopt_long_spec_from_meta()',
            schema  => 'array*', # XXX envres
            description => <<'_',

If you already call <pm:Perinci::Sub::GetArgs::Argv>'s
`gen_getopt_long_spec_from_meta()`, you can pass the _full_ enveloped result
here, to avoid calculating twice. What will be useful for the function is the
extra result in result metadata (`func.*` keys in `$res->[3]` hash).

_
        },
        per_arg_json => {
            schema => 'bool',
            summary => 'Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv',
        },
        per_arg_yaml => {
            schema => 'bool',
            summary => 'Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv',
        },
        lang => {
            schema => 'str*',
        },
    },
    result => {
        schema => 'hash*',
    },
};
sub gen_cli_doc_data_from_meta {
    require Getopt::Long::Negate::EN;

    my %args = @_;

    my $lang = $args{lang};
    my $meta = $args{meta} or return [400, 'Please specify meta'];
    my $common_opts = $args{common_opts};
    unless ($args{meta_is_normalized}) {
        require Perinci::Sub::Normalize;
        $meta = Perinci::Sub::Normalize::normalize_function_metadata($meta);
    }
    my $ggls_res = $args{ggls_res} // do {
        require Perinci::Sub::GetArgs::Argv;
        Perinci::Sub::GetArgs::Argv::gen_getopt_long_spec_from_meta(
            meta=>$meta, meta_is_normalized=>1, common_opts=>$common_opts,
            per_arg_json => $args{per_arg_json},
            per_arg_yaml => $args{per_arg_yaml},
        );
    };
    $ggls_res->[0] == 200 or return $ggls_res;

    my $args_prop = $meta->{args} // {};
    my $clidocdata = {
        option_categories => {},
        example_categories => {},
    };

    my %opts;
  GEN_LIST_OF_OPTIONS: {
        my $ospecs = $ggls_res->[3]{'func.specmeta'};
        # separate groupable aliases because they will be merged with the
        # argument options
        my (@k, @k_aliases);
      OSPEC1:
        for (sort keys %$ospecs) {
            my $ospec = $ospecs->{$_};
            {
                last unless $ospec->{is_alias};
                next if $ospec->{is_code};
                my $arg_spec = $args_prop->{$ospec->{arg}};
                my $alias_spec = $arg_spec->{cmdline_aliases}{$ospec->{alias}};
                next if $alias_spec->{summary};
                push @k_aliases, $_;
                next OSPEC1;
            }
            push @k, $_;
        }

        my %negs; # key=arg, only show one negation form for each arg option

      OSPEC2:
        while (@k) {
            my $k = shift @k;
            my $ospec = $ospecs->{$k};
            my $opt;
            my $optkey;

            if ($ospec->{is_alias} || defined($ospec->{arg})) {
                my $arg_spec;
                my $alias_spec;

                if ($ospec->{is_alias}) {
                    # non-groupable alias

                    my $real_opt_ospec = $ospecs->{ $ospec->{alias_for} };

                    $arg_spec = $args_prop->{ $ospec->{arg} };
                    $alias_spec = $arg_spec->{cmdline_aliases}{$ospec->{alias}};
                    my $rimeta = rimeta($alias_spec);
                    $optkey = _fmt_opt($arg_spec, $ospec);
                    $opt = {
                        opt_parsed => $ospec->{parsed},
                        orig_opt => $k,
                        is_alias => 1,
                        alias_for => $ospec->{alias_for},
                        summary => $rimeta->langprop({lang=>$lang}, 'summary') //
                            "Alias for "._dash_prefix($real_opt_ospec->{parsed}{opts}[0]),
                        description =>
                            $rimeta->langprop({lang=>$lang}, 'description'),
                    };
                } else {
                    # an option for argument

                    $arg_spec = $args_prop->{$ospec->{arg}};
                    my $rimeta = rimeta($arg_spec);
                    $opt = {
                        opt_parsed => $ospec->{parsed},
                        orig_opt => $k,
                    };

                    # for bool, only display either the positive (e.g. --bool)
                    # or the negative (e.g. --nobool) depending on the default
                    if (defined($ospec->{is_neg})) {
                        my $default = $arg_spec->{default} //
                            $arg_spec->{schema}[1]{default};
                        next OSPEC2 if  $default && !$ospec->{is_neg};
                        next OSPEC2 if !$default &&  $ospec->{is_neg};
                        if ($ospec->{is_neg}) {
                            next OSPEC2 if $negs{$ospec->{arg}}++;
                        }
                    }

                    if ($ospec->{is_neg}) {
                        # for negative option, use negative summary instead of
                        # regular (positive sentence) summary
                        $opt->{summary} =
                            $rimeta->langprop({lang=>$lang}, 'summary.alt.bool.not');
                    } elsif (defined $ospec->{is_neg}) {
                        # for boolean option which we show the positive, show
                        # the positive summary if available
                        $opt->{summary} =
                            $rimeta->langprop({lang=>$lang}, 'summary.alt.bool.yes') //
                                $rimeta->langprop({lang=>$lang}, 'summary');
                    } elsif (($ospec->{parsed}{type}//'') eq 's@') {
                        # for array of string that can be specified via multiple
                        # --opt, show singular version of summary if available.
                        # otherwise show regular summary.
                        $opt->{summary} =
                            $rimeta->langprop({lang=>$lang}, 'summary.alt.plurality.singular') //
                                $rimeta->langprop({lang=>$lang}, 'summary');
                    } else {
                        $opt->{summary} =
                            $rimeta->langprop({lang=>$lang}, 'summary');
                    }
                    $opt->{description} =
                        $rimeta->langprop({lang=>$lang}, 'description');

                    # find aliases that can be grouped together with this option
                    my @aliases;
                    my $j = $#k_aliases;
                    while ($j >= 0) {
                        my $aospec = $ospecs->{ $k_aliases[$j] };
                        {
                            last unless $aospec->{arg} eq $ospec->{arg};
                            push @aliases, $aospec;
                            splice @k_aliases, $j, 1;
                        }
                        $j--;
                    }

                    $optkey = _fmt_opt($arg_spec, $ospec, @aliases);
                }

                $opt->{arg_spec} = $arg_spec;
                $opt->{alias_spec} = $alias_spec if $alias_spec;

                # include keys from func.specmeta
                for (qw/arg fqarg is_base64 is_json is_yaml/) {
                    $opt->{$_} = $ospec->{$_} if defined $ospec->{$_};
                }

                # include keys from arg_spec
                for (qw/req pos slurpy greedy is_password links tags/) {
                    $opt->{$_} = $arg_spec->{$_} if defined $arg_spec->{$_};
                }

                {
                    # we don't want argument options to end up in "Other" like
                    # --help or -v, they are put at the end. so if an argument
                    # option does not have category, we'll put it in the "main"
                    # category.
                    local $arg_spec->{tags} = ['category0:main']
                        if !$arg_spec->{tags} || !@{$arg_spec->{tags}};
                    _add_category_from_spec($clidocdata->{option_categories},
                                            $opt, $arg_spec, "options", 1);
                }
                _add_default_from_arg_spec($opt, $arg_spec);

            } else {
                # option from common_opts

                my $spec = $common_opts->{$ospec->{common_opt}};

                # for bool, only display either the positive (e.g. --bool)
                # or the negative (e.g. --nobool) depending on the default
                my $show_neg = $ospec->{parsed}{is_neg} && $spec->{default};

                local $ospec->{parsed}{opts} = do {
                    # XXX check if it's single-letter, get first
                    # non-single-letter
                    my @opts = Getopt::Long::Negate::EN::negations_for_option(
                        $ospec->{parsed}{opts}[0]);
                    [ $opts[0] ];
                } if $show_neg;

                $optkey = _fmt_opt($spec, $ospec);
                my $rimeta = rimeta($spec);
                $opt = {
                    opt_parsed => $ospec->{parsed},
                    orig_opt => $k,
                    common_opt => $ospec->{common_opt},
                    common_opt_spec => $spec,
                    summary => $show_neg ?
                        $rimeta->langprop({lang=>$lang}, 'summary.alt.bool.not') :
                            $rimeta->langprop({lang=>$lang}, 'summary'),
                    (schema => $spec->{schema}) x !!$spec->{schema},
                    ('x.schema.entity' => $spec->{'x.schema.entity'}) x !!$spec->{'x.schema.entity'},
                    ('x.schema.element_entity' => $spec->{'x.schema.element_entity'}) x !!$spec->{'x.schema.element_entity'},
                    description =>
                        $rimeta->langprop({lang=>$lang}, 'description'),
                    (default => $spec->{default}) x !!(exists($spec->{default}) && !$show_neg),
                };

                _add_category_from_spec($clidocdata->{option_categories},
                                        $opt, $spec, "options", 1);

            }

            $opts{$optkey} = $opt;
        }

        # link ungrouped alias to its main opt
      OPT1:
        for my $k (keys %opts) {
            my $opt = $opts{$k};
            next unless $opt->{is_alias} || $opt->{is_base64} ||
                $opt->{is_json} || $opt->{is_yaml};
            for my $k2 (keys %opts) {
                my $arg_opt = $opts{$k2};
                next if $arg_opt->{is_alias} || $arg_opt->{is_base64} ||
                    $arg_opt->{is_json} || $arg_opt->{is_yaml};
                next unless defined($arg_opt->{arg}) &&
                    $arg_opt->{arg} eq $opt->{arg};
                $opt->{main_opt} = $k2;
                next OPT1;
            }
        }

    } # GEN_LIST_OF_OPTIONS
    $clidocdata->{opts} = \%opts;

  GEN_USAGE_LINE: {
        my @args;
        my %args_prop = %$args_prop; # copy because we want to iterate & delete
        my $max_pos = -1;
        for (values %args_prop) {
            $max_pos = $_->{pos}
                if defined($_->{pos}) && $_->{pos} > $max_pos;
        }
        my $pos = 0;
        while ($pos <= $max_pos) {
            my ($arg, $arg_spec);
            for (keys %args_prop) {
                $arg_spec = $args_prop{$_};
                if (defined($arg_spec->{pos}) && $arg_spec->{pos}==$pos) {
                    $arg = $_;
                    last;
                }
            }
            $pos++;
            next unless defined($arg);
            if ($arg_spec->{slurpy} // $arg_spec->{greedy}) {
                # try to find the singular form
                $arg = $arg_spec->{'x.name.singular'}
                    if $arg_spec->{'x.name.is_plural'} &&
                    defined $arg_spec->{'x.name.singular'};
            }
            if ($arg_spec->{req}) {
                push @args, "<$arg>";
            } else {
                push @args, "[$arg]";
            }
            $args[-1] .= " ..." if ($arg_spec->{slurpy} // $arg_spec->{greedy});
            delete $args_prop{$arg};
        }

        # XXX utilize information from args_rels

        require Getopt::Long::Util;
        my @opts;
        for my $ospec (sort keys %{ $ggls_res->[3]{'func.specmeta'} }) {
            my $ospecmeta = $ggls_res->[3]{'func.specmeta'}{$ospec};

            my $argprop = defined $ospecmeta->{arg} ? $args_prop{ $ospecmeta->{arg} } : undef;
            # only include args that have not been mentioned in positional
            next if defined $ospecmeta->{arg} && !$argprop;
            # only inlude common options that are not a specific action that are
            # invoked on its own

            my $copt = defined $ospecmeta->{common_opt} ? $common_opts->{ $ospecmeta->{common_opt} } : undef;
            next if defined $ospecmeta->{common_opt} && $copt->{usage};
            push @opts, "[".Getopt::Long::Util::humanize_getopt_long_opt_spec({
                separator=>" | ",
                value_label=>(
                    $argprop ?
                        ($argprop->{'x.cli.opt_value_label'} // $argprop->{caption}) :
                        ($copt->{value_label})
                    ),
            }, $ospec)."]";
        }

        $clidocdata->{compact_usage_line} = "[[prog]]".
            (keys(%args_prop) || keys(%$common_opts) ? " [options]" : ""). # XXX translatable?
            (@args ? " ".join(" ", @args) : "");
        $clidocdata->{usage_line} = "[[prog]]".
            (@opts+@args ? " ".join(" ", @opts, @args) : "");
    } # GEN_USAGE_LINE

    # filter and format examples
    my @examples;
    {
        my $examples = $meta->{examples} // [];
        my $has_cats = _has_cats($examples);

        for my $eg (@$examples) {
            my $rimeta = rimeta($eg);
            my $argv;
            my $cmdline;
            if (defined($eg->{src})) {
                # we only show shell command examples
                if ($eg->{src_plang} =~ /^(sh|bash)$/) {
                    $cmdline = $eg->{src};
                } else {
                    next;
                }
            } else {
                require String::ShellQuote;
                if ($eg->{argv}) {
                    $argv = $eg->{argv};
                } else {
                    require Perinci::Sub::ConvertArgs::Argv;
                    my $res = Perinci::Sub::ConvertArgs::Argv::convert_args_to_argv(
                        args => $eg->{args}, meta => $meta, use_pos => 1);
                    return err($res, 500, "Can't convert args to argv")
                        unless $res->[0] == 200;
                    $argv = $res->[2];
                }
                $cmdline = "[[prog]]";
                for my $arg (@$argv) {
                    my $qarg = String::ShellQuote::shell_quote($arg);
                    $cmdline .= " $qarg"; # XXX markup with color?
                }
            }
            my $egdata = {
                cmdline      => $cmdline,
                summary      => $rimeta->langprop({lang=>$lang}, 'summary'),
                description  => $rimeta->langprop({lang=>$lang}, 'description'),
                example_spec => $eg,
            };
            # XXX show result from $eg
            _add_category_from_spec($clidocdata->{example_categories},
                                    $egdata, $eg, "examples", $has_cats);
            push @examples, $egdata;
        }
    }
    $clidocdata->{examples} = \@examples;

    [200, "OK", $clidocdata];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

 use Perinci::Sub::To::CLIDocData qw(gen_cli_doc_data_from_meta);
 my $clidocdata = gen_cli_doc_data_from_meta(meta => $meta);

Sample function metadata (C<$meta>):

# CODE: require Perinci::Examples::CLI; $Perinci::Examples::CLI::SPEC{demo_cli_opts_shorter};

Sample result:

# CODE: require Perinci::Examples::CLI; require Perinci::Sub::To::CLIDocData; Perinci::Sub::To::CLIDocData::gen_cli_doc_data_from_meta(meta=>$Perinci::Examples::CLI::SPEC{demo_cli_opts_shorter});

For a more complete sample, see function metadata for C<demo_cli_opts> in
L<Perinci::Examples::CLI>.


=head1 RINCI

Observed function argument attribute: C<x.cli.opt_value_label>, C<caption>, C<>.


=head1 SEE ALSO

L<Perinci::CmdLine>, L<Perinci::CmdLine::Lite>

L<Pod::Weaver::Plugin::Rinci>
