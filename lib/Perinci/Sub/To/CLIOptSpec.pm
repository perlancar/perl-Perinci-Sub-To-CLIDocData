package Perinci::Sub::To::CLIOptSpec;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(gen_cli_opt_spec_from_meta);

$SPEC{gen_cli_opt_spec_from_meta} = {
    v => 1.1,
    summary => 'From Rinci function metadata, generate structure convenient '.
        'for producing CLI help/usage',
    description => <<'_',

This function calls `Perinci::Sub::GetArgs::Argv`'s
`gen_getopt_long_spec_from_meta()` and post-processes it. The resulting data
structure contains information that is convenient to use when one produces a
help message for a command-line program.

Sample ouput:

    XXXX

_
    args => {
        meta => {
            schema => 'hash*', # XXX rifunc
            req => 1,
            pos => 0,
        },
    },
    result => {
        schema => 'hash*',
    },
};
sub gen_cli_opt_spec_from_meta {
    require Perinci::Sub::GetArgs::Argv;

    my %args = @_;

    my $meta = $args{meta};
    my $res = Perinci::Sub::GetArgs::Argv::gen_getopt_long_spec_from_meta(
        meta => $meta);
    $res->[0] == 200 or return $res;

    # sort function args by position

    $res;
}

1;
# ABSTRACT: From Rinci function metadata, generate structure convenient for producing CLI help/usage

=head1 SYNOPSIS

 use Perinci::Sub::To::CLIOptSpec qw(gen_cli_opt_spec_from_meta);
 my $cliospec = gen_cli_opt_spec_from_meta(meta => $meta);

=cut
