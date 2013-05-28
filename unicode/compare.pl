#!/usr/bin/perl

# This module creates the TeX files in the test/ folder, which are used to test the mapping defined by TeX::Unicode.
#
# Usage: ./make_tests.pl

use warnings;
use strict;
$|++;

use IO::File;

use Encode;
use TeXEncode_1_1;
#use TeX::Encode 1.3;
#use XML::Parser;
use List::MoreUtils qw(uniq);
use TeX::Unicode qw(%CODES);

my %unimath;
my $fh = IO::File->new("unimathsymbols.txt", 'r');
while (<$fh>) {
    next if /^#/;
    my @fields = split / *\^ */;
    $unimath{hex($fields[0])} = $fields[2] if $fields[2] ne '';
    #print "$fields[0]:$fields[2].\n";
}

for (sort {$a <=> $b}
         (uniq(map {0+$_}   (keys %CODES),
               map {0+$_}   (keys %unimath),
               map {ord $_} (keys %TeX::Encode::charmap::CHAR_MAP),
               map {ord $_} (keys %TeXEncode_1_1::LATEX_Escapes)))) {
    my $num = $_;
    my $str = chr($_);
    my $self = $CODES{$num};
    my $other1 = $TeX::Encode::charmap::CHAR_MAP{$str};
    my $other2 = $TeXEncode_1_1::LATEX_Escapes{$str};
    my $other3 = $unimath{$num};
    $self =~ s[\\ensuremath{(.*)}][$1] if defined $self;
    $other1 =~ s[^\$(.*)\$$][\\ensuremath{$1}] if defined $other1;
    $other2 =~ s[^\$(.*)\$$][\\ensuremath{$1}] if defined $other2;
    $other3 =~ s[^\$(.*)\$$][\\ensuremath{$1}] if defined $other3;
    if (defined $other3) {
    unless (defined $self and defined $other3 and $other3 eq $self) {
        printf("%04x %s", $num, encode_utf8(chr($num)));
        # XML is better than XML.old
        # XML is better than LATEX_Escapes when they conflict
        # XML is a superset of LATEX_Escapes
        #print(" ($other2)") if defined $other2;
        # XML is better than CHAR_MAP when they conflict
        # There are some in CHARP_MAP that are missing from XML
        #print(" ($other1)") if defined $other1;
        print(" ($other3)") if defined $other3;
        print(" [$self]") if defined $self;
        print("\n");
    }
    }
}

# Old code to parse unicode.xml
#my $p = XML::Parser->new(Style => 'Stream', Pkg => 'main');
#$p->parsefile('-');

my ($number, $mode) = (undef, undef);
my $tag;
my ($latex, $ams);

my %codes;

sub PI { }

sub StartTag {
    my ($e, $name) = @_;
    if ($name eq 'character') {
        ($number, $mode) = ($_{'dec'}, $_{'mode'});
        return if $number =~ /-/; # Skip number ranges
        ($latex, $ams) = (undef, undef); # Reset the possible tokens

        $mode = 'math' if defined $mode and $mode eq 'unknown' or
            grep {hex $_ == $number} qw(
                0x2212 0x2254 0x25a0 0x2605 0x2660 0x2663 0x2713 0x2720); # TODO: check these

        $mode = 'text' if grep {hex $_ == $number} qw(
            0x00a0 0x00ad 0x030a 0x0328 0x2039 0x203a); # TODO: check these
    }
    $tag = $_;
}

sub latex { if ($number >= 0x2000 and $number <= 0xffff) { $codes{0+$number} = $latex; } }
sub ams   { if ($number >= 0x2000 and $number <= 0xffff) { $codes{0+$number} = $ams;   } }

sub EndTag {
  if ($_ eq '</character>' and $number !~ /-/) {
        if ($number < 0x80) { } # No escapes 
        elsif (not defined $latex and not defined $ams) { }
        elsif (not defined $latex) { ams; }
        elsif (not defined $ams) { latex; }
        else {
            my $test = $latex;
            $test =~ s[\\ensuremath\{(.*)\}][$1];

            if ($test =~ /^\\not/) { ams; } # Avoid "\not"
            elsif ($test =~ /\{.+\}/) { ams; } # Avoid macros with non-empty arguments
            elsif ($test !~ /\\/) { ams; } # Avoid non-macros (e.g. ":=")
            elsif ($number == 0x222c) { ams; } # \iint
            elsif ($number == 0x222d) { ams; } # \iiint
            elsif ($number == 0x2272) { ams; } # \lesssim
            elsif ($number == 0x2273) { ams; } # \gtrsim
            elsif ($number == 0x2217) { ams; } # \ast
            else { latex; }
        }
    }
}

sub cleanCode {
    # These capitol letters don't actually exist.  Use Roman letters instead.
    s[\\Alpha\b][{A}]g;
    s[\\Beta\b][{B}]g;
    s[\\Epsilon\b][{E}]g;
    s[\\Zeta\b][{Z}]g;
    s[\\Eta\b][{H}]g;
    s[\\Iota\b][{I}]g;
    s[\\Kappa\b][{K}]g;
    s[\\Mu\b][{M}]g;
    s[\\Nu\b][{N}]g;
    s[\\Rho\b][{R}]g;
    s[\\Tau\b][{T}]g;
    s[\\Chi\b][{X}]g;

    #s[\\omicron\b][{o}]g;
    s[\\text(Theta|theta|vartheta|phi)\b][\\ensuremath{\\$1}]g; # This one already has an ensure math around it
    s[\\textfrac\b][\\frac]g;
#    s[\\koppa\b][\\qoppa]g;
#    s[\\Koppa\b][\\Qoppa]g;
#    s[\\digamma\b][\\ddigamma]g;
#    s[\\Digamma\b][\\Ddigamma]g;
    s[\\mbox{\\texteuro}][\\texteuro];
    s[\\mathmit\b][\\mathit];

    s[^(\\[^\\])$][$1\{\}]g; # Ensure that single macros that can take arguments already have their arguments
    s[{(\\d+dot)}][{$1\{\}}]g;

    s[^(\\\W){(\w)}$][$1$2]g; # translate "\'{x}" to "\'x"
    s[\{\{([^{}]*)\}\}][{$1}]g; # Remove doubled up {{x}} (but dont do {{x}y{z}})
    s[\\ensuremath{\\ensuremath{([^{}]*)}}][\\ensuremath{$1}]g;
}

#sub EndTag {
#    my ($e, $name) = @_;
#    # do something with end tags
#}
    
sub Text {
    my ($e, $data) = @_;
    s[^\s*(\S*)\s*$][$1]; # Trim whitespace

    return if $_ eq ""; # Skip if empty
    return if m[\\El] or m[\\ElsevierGlyph] or m[\\fontencoding] or m[\\cyrchar]; # Avoid these codes

    $mode = 'text' if m[\\texteuro];
    s[^(.+)$][\\ensuremath\{$1\}]
        if not m[\\ensuremath\b]
        and (defined $mode and $mode eq 'math' # Ensure math if the start tag says it's math
             or m[^\\math]); # or it is one of "\mathbf" and friends

    $latex = $_ if $tag eq '<latex>';
    $ams = $_ if $tag eq '<AMS>';
}
