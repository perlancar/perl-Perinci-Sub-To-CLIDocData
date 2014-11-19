package Perinci::Sub::To::CLIOptSpec;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Perinci::Object;

our %SPEC;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(gen_cli_opt_spec_from_meta);

sub _fmt_opt {
    my $spec = shift;
    my @parsed = @_;
    my @res;
    my $i = 0;
    for my $parsed (@parsed) {
        my $j = 0;
        for (@{ $parsed->{opts} }) {
            my $opt = length($_)>1 ? "--$_" : "-$_";
            if ($i==0 && $j==0) {
                if ($parsed->{type}) {
                    if ($spec->{'x.schema.entity'}) {
                        $opt .= "=".$spec->{'x.schema.entity'};
                    } else {
                        $opt .= "=$parsed->{type}";
                    }
                }
            }
            push @res, $opt;
            $j++;
        }
        $i++;
    }
    join ", ", @res;
}

$SPEC{gen_cli_opt_spec_from_meta} = {
    v => 1.1,
    summary => 'From Rinci function metadata, generate structure convenient '.
        'for producing CLI help/usage',
    description => <<'_',

This function calls `Perinci::Sub::GetArgs::Argv`'s
`gen_getopt_long_spec_from_meta()` (or receive it, if passed, to avoid
calculating twice) and post-processes it: produce command usage line, format the
options, include information from metadata, group the options by category. The
resulting data structure is convenient to use when one produces a help message
for a command-line program.

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

If you already call `Perinci::Sub::GetArgs::Argv`'s
`gen_getopt_long_spec_from_meta()`, you can pass the _full_ enveloped result
here, to avoid calculating twice. What will be useful for the function is the
extra result in result metadata (`func.*` keys in `$res->[3]` hash).

_
        },
        lang => {
            schema => 'str*',
        },
    },
    result => {
        schema => 'hash*',
    },
};
sub gen_cli_opt_spec_from_meta {
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
        );
    };
    $ggls_res->[0] == 200 or return $ggls_res;

    my $args_prop = $meta->{args} // {};
    my $cliospec = {};

    # generate usage line
    {
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
            next unless defined($arg);
            if ($arg_spec->{req}) {
                push @args, "<$arg>";
            } else {
                push @args, "[$arg]";
            }
            push @args, "..." if $arg_spec->{greedy};
            delete $args_prop{$arg};
            $pos++;
        }
        unshift @args, "[options]" if keys %args_prop; # XXX translatable?
        $cliospec->{usage_line} = "[[prog]]".
            (@args ? " ".join(" ", @args) : "");
    }

    # group options by category, combine options with its alias(es) that can be
    # combined
    my %opts;
    {
        my $ospecs = $ggls_res->[3]{'func.specmeta'};
        for my $k (keys %$ospecs) {
            my $ospec = $ospecs->{$k};
            my $ok;
            if (defined $ospec->{arg}) {
                my $arg_spec = $args_prop->{$ospec->{arg}};
                $ok = _fmt_opt($arg_spec, $ospec->{parsed});
                my $rimeta = rimeta($arg_spec);
                $opts{$ok} = {
                    category => "x",
                    summary => $rimeta->langprop({lang=>$lang}, 'summary'),
                    description =>
                        $rimeta->langprop({lang=>$lang}, 'description'),
                };
            } else {
                $ok = _fmt_opt($common_opts, $ospec->{parsed});
                my $rimeta = rimeta($common_opts->{$ospec->{common_opt}});
                $opts{$ok} = {
                    category => "Common options", # XXX translatable?
                    summary => $rimeta->langprop({lang=>$lang}, 'summary'),
                    description =>
                        $rimeta->langprop({lang=>$lang}, 'description'),
                };
            }
        }
    }
    $cliospec->{opts} = \%opts;

    # XXX: group groupable aliases
    # XXX: use negative form if default is active (and use alt neg)
    # XXX: add non-grouped aliases
    # XXX: proper category

    [200, "OK", $cliospec];
}

1;
# ABSTRACT: Generate data structure convenient for producing CLI help/usage

=head1 SYNOPSIS

 use Perinci::Sub::To::CLIOptSpec qw(gen_cli_opt_spec_from_meta);
 my $cliospec = gen_cli_opt_spec_from_meta(meta => $meta);


=head1 SEE ALSO

L<Perinci::CmdLine>, L<Perinci::CmdLine::Lite>

L<Pod::Weaver::Plugin::Rinci>

