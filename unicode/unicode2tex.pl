#!/usr/bin/perl

# http://www.w3.org/TR/xml-entity-names/
# http://www.w3.org/2003/entities/2007xml/unicode.xml

use warnings;
use strict;
$|++;

use TeX::Encode;
use XML::Parser;

my ($number, $mode) = (undef, undef);
my $tag;
my ($latex, $mathlatex, $ams);

my ($TEST_TEX, $COMPARE, $MAKE_MODULE) = (0, 0, 1);

my %codes;

my $p = XML::Parser->new(Style => 'Stream', Pkg => 'main');
$p->parsefile('-');

$codes{0x00ad} = '\-';
$codes{0x0192} = '\textflorin';
$codes{0x0237} = '\j';
$codes{0x02c6} = '\^{}';
$codes{0x02dc} = '\~{}';
$codes{0x2013} = '--';
$codes{0x2014} = '---';
$codes{0x201a} = '\quotesinglbase';
$codes{0x201e} = '\quotedblbase';
$codes{0x2329} = '\ensuremath{\langle}';
$codes{0x232a} = '\ensuremath{\rangle}';


if ($TEST_TEX) {
    print <<'EOT';
    \documentclass[11pt]{article}
    \usepackage[T1]{fontenc}
    %\usepackage{cite}
    \usepackage{amssymb}
    \usepackage{MnSymbol}
    \usepackage{amsmath}
    \usepackage{textcomp}
    \usepackage{pifont}
    %\usepackage[tone]{tipa}
    %%\usepackage{teubner}
    %\usepackage[greek]{babel}
    %%\usepackage[mathscr,mathcal]{euscript}
    \usepackage{mathrsfs}
    %\usepackage{txfonts}
    %\usepackage{pxfonts}
    \usepackage{wasysym}
    %\usepackage{stmaryrd}
    \usepackage{mathdesign}
    \begin{document}
    
EOT

    for (sort {$a <=> $b} keys %codes) {
        print sprintf("%04x %s %s\n\n", $_, $_, $codes{$_});
    }

    print "\\end{document}\n";
}


if ($COMPARE) {
    for (sort keys %TeX::Encode::LATEX_Escapes) {
        $number = ord($_);
        my $str = $_;
        my $self = $codes{$number};
        my $other = $TeX::Encode::LATEX_Escapes{$str};
        $self =~ s[^\$(.*)\$$][\\ensuremath{$1}];
        $other =~ s[^\$(.*)\$$][\\ensuremath{$1}];
        print sprintf("%04x %s -- %s\n", $number, $other, $self) if $other ne $self;
    }
}

if ($MAKE_MODULE) {
    print <<'EOT';
package TeX::Unicode;
use warnings;
use strict;

use Exporter qw(import);

our @EXPORT = qw(unicode2tex);
our @EXPORT_OK = qw();

my %CODES;

sub unicode2tex {
    my ($str) =  @_;
    $str =~ s[([^\x00-\x80])][\{@{[$CODES{$1} or
         warn "Unknown Unicode charater: $1 ", sprintf("0x%x", ord($1)) and
         $1]}\}]g;
    return $str;
}

%CODES = (
EOT
    for (sort {$a <=> $b} keys %codes) {
        my $x = $codes{$_};
        $x =~ s[\\][\\\\]g;
        $x =~ s['][\\']g;
        print sprintf("    0x%04x => '%s',\n", $_, $x);
    }
    print <<'EOT';
    );
1;
EOT
}

sub PI { }

sub StartTag {
    my ($e, $name) = @_;
    if ($name eq 'character') {
        ($number, $mode) = ($_{'dec'}, $_{'mode'});
        return if $number =~ /-/;
        ($latex, $mathlatex, $ams) = (undef, undef, undef);
#        print sprintf("\n%04x %s", $number, chr($number));
        $mode = 'math' if defined $mode and $mode eq 'unknown' or
            grep {hex $_ == $number} qw(
                0x030a 0x2212 0x2254 0x25a0 0x2605 0x2660 0x2663 0x2713 0x2720);

        $mode = 'text' if grep {hex $_ == $number} qw(
            0x00a0 0x00ad 0x0328 0x2039 0x203a);
    }
    $tag = $_;
}

sub latex {
#    if ($latex =~ m[^(\\\W){(\w)}$]) {
#        $codes{$number} = $1 . $2;
#    } elsif ($mode eq 'math') {
#        $codes{$number} = "\\ensuremath{$latex}";
#    } else {
        $codes{$number} = $latex;
#    }
#    print sprintf("%04x %s %s\n", $number, chr($number), $latex);
}
sub ams {
#    if ($mode eq 'math') {
#        $codes{$number} = "\\ensuremath{$ams}";
#    } else {
        $codes{$number} = $ams;
#    }
#    print sprintf("%04x %s %s\n", $number, chr($number), $ams);
}

sub EndTag {
#    print "$latex $mathlatex $ams+++++\n" if $number == 0x00ac;
    if ($_ eq '</character>' and $number !~ /-/) {
        if ($number < 0x80) { }
        elsif (not defined $latex and not defined $ams) { }
        elsif (not defined $ams) { latex; }
        elsif (defined $mathlatex) { latex; }
        elsif (not defined $latex) { ams; }
        else {
            my $test = $latex;
            $test =~ s[\\ensuremath\{(.*)\}][$1];

            if ($test =~ /^\\not/) { ams; }
            elsif ($test =~ /\{/) { ams; }
            elsif ($test !~ /\\/) { ams; }
            elsif ($number == 0x222c) { ams; }
            elsif ($number == 0x222d) { ams; }
            else { latex; }
        }
    }
}


 #0024 $ <latex> \textdollar <mathlatex> \$
#
#002e . <latex> . <IEEE> \ldotp
#003a : <latex> : <AMS> \colon <IEEE> \colon
#
#003c < <latex> $<$ <AMS> \less
#003e > <latex> $>$ <AMS> \greater
#005b [ <latex> [ <AMS> \lbrack <IEEE> \lbrack
#005c \ <latex> \textbackslash <mathlatex> \backslash <AMS> \backslash <IEEE> \backslash
#005d ] <latex> ] <AMS> \rbrack <IEEE> \rbrack
#005e ^ <latex> \^{} <AMS> \textasciicircumflex


#sub EndTag {
#    my ($e, $name) = @_;
#    # do something with end tags
#}
    
sub Text {
    my ($e, $data) = @_;
    s[^\s*(\S*)\s*$][$1];
    return if $_ eq "";
    return if m[\\El] or m[\\ElsevierGlyph] or m[\\fontencoding] or m[\\cyrchar];
    $mode = 'math' if m[^\\math] and $tag eq '<latex>';
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

    s[\\omicron\b][{o}]g;
    s[\\textTheta\b][\\Theta]g;
    s[\\texttheta\b][\\ensuremath{\\theta}]g;
    s[\\textphi\b][\\ensuremath{\\phi}]g;
    s[^\\textvartheta$][\\ensuremath{\\vartheta}]g;
    s[\\textfrac][\\frac]g;
#    s[\\koppa\b][\\qoppa]g;
#    s[\\Koppa\b][\\Qoppa]g;
#    s[\\digamma\b][\\ddigamma]g;
#    s[\\Digamma\b][\\Ddigamma]g;

    s[^(\\.)$][$1\{\}]g;
    s[^(\\d+dot)$][$1\{\}]g;

    s[^(\\\W){(\w)}$][$1$2]g;
    s[^(.+)$][\\ensuremath\{$1\}] if defined $mode and $mode eq 'math';
    s[\{\{(.*?)\}\}][{$1}]g;

    $latex = $_ if $tag eq '<latex>';
    $mathlatex = $_ if $tag eq '<mathlatex>';
    $ams = $_ if $tag eq '<AMS>';
#    if ($tag eq '<latex>' or
#        $tag eq '<varlatex>' or
#        $tag eq '<mathlatex>' or
#        $tag eq '<AMS>' or
#        $tag eq '<IEEE>') { print " $tag $_" }
#        $tag eq '<IEEE>') { print sprintf("$tag '\\x{%04x}' => '{%s}' ", $number, $_); }

    # do something with text nodes
}

=end

use XML::Simple qw(:strict);;

my $ref = XMLin("-");
print join("\n", keys %$ref);
#<character(.*?)>
#id=
