#!/usr/bin/perl
#
# Basic tests for podlators.
#
# This test case uses a single sample file and runs it through all available
# formatting modules, comparing the results to known-good output that's
# included with the package.  This provides a general sanity check that the
# modules are working properly.
#
# New regression tests and special cases should probably not be added to the
# sample input file, since updating all the output files is painful.  Instead,
# the machinery to run small POD snippets through the specific formatter being
# tested should probably be used instead.
#
# Copyright 2001, 2002, 2004, 2006, 2009, 2012, 2014
#     Russ Allbery <rra@cpan.org>
#
# This program is free software; you may redistribute it and/or modify it
# under the same terms as Perl itself.

use 5.006;
use strict;
use warnings;

use File::Spec;
use FileHandle;
use Test::More tests => 15;

# Check that all the modules can be loaded.
BEGIN {
    use_ok('Pod::Man');
    use_ok('Pod::Text');
    use_ok('Pod::Text::Color');
    use_ok('Pod::Text::Overstrike');
    use_ok('Pod::Text::Termcap');
}

# Flush output, since otherwise our diag messages come after other tests.
local $| = 1;

# Hard-code configuration for Term::Cap to get predictable results.
local $ENV{COLUMNS}  = 80;
local $ENV{TERM}     = 'xterm';
local $ENV{TERMPATH} = File::Spec->catdir('t', 'data', 'termcap');
local $ENV{TERMCAP}  = 'xterm:co=#80:do=^J:md=\\E[1m:us=\\E[4m:me=\\E[m';

# Find the source of the test file.
my $INPUT = File::Spec->catdir('t', 'data', 'basic.pod');

# Map of translators to the file containing the formatted output to compare
# against.
my %OUTPUT = (
    'Pod::Man'              => File::Spec->catdir('t', 'data', 'basic.man'),
    'Pod::Text'             => File::Spec->catdir('t', 'data', 'basic.txt'),
    'Pod::Text::Color'      => File::Spec->catdir('t', 'data', 'basic.clr'),
    'Pod::Text::Overstrike' => File::Spec->catdir('t', 'data', 'basic.ovr'),
    'Pod::Text::Termcap'    => File::Spec->catdir('t', 'data', 'basic.cap'),
);

# Options to pass to all formatting modules.  Match the pod2text default.
my @OPTIONS = (sentence => 0);

# Walk through teach of the modules and format the sample file, checking to
# ensure the results match the pre-generated file.
for my $module (sort keys %OUTPUT) {
    my $parser = $module->new(@OPTIONS);
    isa_ok($parser, $module, 'parser object');

    # Store the output into a Perl variable instead of a file.
    my $got;
    $parser->output_string(\$got);

    # Run the formatting module.
    $parser->parse_file($INPUT);

    # If the test module is Pod::Man, strip off the header.  This test does
    # not attempt to compare it, since it contains version numbers that
    # change.
    if ($module eq 'Pod::Man') {
        $got =~ s{ \A .* \n [.]nh \n }{}xms;
    }

    # Slurp in the expected output.
    my $output = FileHandle->new($OUTPUT{$module}, 'r')
      or BAIL_OUT("cannot open $OUTPUT{$module}: $!");
    my $expected = do { local $/ = undef; <$output> };
    $output->close or BAIL_OUT("cannot read $OUTPUT{$module}: $!");

    # OS/390 is EBCDIC, which apparently uses a different character for ESC.
    # Try to convert so that the test still works.
    if ($^O eq 'os390' && $module eq 'Pod::Text::Termcap') {
        $got =~ tr{\033}{\047};
    }

    # Check the output.  If it doesn't match, save the erroneous output in a
    # file for later inspection.
    if (!ok($got eq $expected, "$module output is correct")) {
        my ($suffix) = ($OUTPUT{$module} =~ m{ [.] ([^.]+) \z }xms);
        my $tmpdir = File::Spec->catdir('t', 'tmp');
        my $outfile = File::Spec->catdir('t', 'tmp', "out$$.$suffix");
        if (!-d $tmpdir) {
            mkdir($tmpdir, 0777);
        }
        $output = FileHandle->new($outfile, 'w')
          or die "Cannot create $outfile for failed output: $!\n";
        print {$output} $got
          or die "Cannot write failed output to $outfile: $!\n";
        $output->close
          or die "Cannot write failed output to $outfile: $!\n";
        diag("Non-matching output left in $outfile");
    }
}
