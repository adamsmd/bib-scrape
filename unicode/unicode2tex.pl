#!/usr/bin/perl

# http://www.w3.org/TR/xml-entity-names/
# XML: http://www.w3.org/2003/entities/2007xml/unicode.xml
# XML.old: http://www.w3.org/Math/characters/unicode.xml

# TeX::Encode 1.3 uses http://www-sop.inria.fr/marelle/tralics/
# TeX::Encode 1.1 uses other modules to reconstruct it

use warnings;
use strict;
$|++;

use IO::File;

use Encode;
use TeXEncode;
use TeX::Encode;
use XML::Parser;
use List::MoreUtils qw(uniq);

my ($number, $mode) = (undef, undef);
my $tag;
my ($latex, $ams);

my ($TEST_TEX, $COMPARE, $MAKE_MODULE) = (1, 0, 0);

my %codes;

my $p = XML::Parser->new(Style => 'Stream', Pkg => 'main');
$p->parsefile('-');

$codes{0x00ad} = '\-'; # Don't want extra {} at the end
$codes{0x0192} = '\textflorin'; # Wrong: \ensuremath{f}
$codes{0x0237} = '\j'; # Missing
$codes{0x02c6} = '\^{}'; # Missing
$codes{0x02dc} = '\~{}'; # Wrong: \texttildelow
$codes{0x2013} = '--'; # Wrong: \textendash
$codes{0x2014} = '---'; # Wrong: \textemdash
$codes{0x201a} = '\quotesinglbase'; # Wrong: ,
$codes{0x201e} = '\quotedblbase'; # Wrong: ,,
$codes{0x2329} = '\ensuremath{\langle}'; # Missing
$codes{0x232a} = '\ensuremath{\rangle}'; # Missing
$codes{0x219c} = '\ensuremath{\arrowwaveleft}'; # Wrong: \arrowwaveright
$codes{0x2244} = '\ensuremath{\nsimeq}'; # Wrong: \nsime

sub start {
    my ($file, @packages) = @_;
    print $file "\\documentclass[11pt]{article}\n\\usepackage[T1]{fontenc}\n";
    print $file "\\usepackage$_\n" for @packages;
    print $file "\\begin{document}\n\n";
}

if ($TEST_TEX) {
    my ($main, $ipa, $greek, $mn, $ding, $letters) =
        map { IO::File->new("test/$_.tex", 'w') } qw(main ipa greek mn ding letters);

    start($main, qw({amssymb} {amsmath} {textcomp} {mathrsfs} {mathabx} {shuffle}));
#    %\usepackage{cite}
#    %\usepackage{amsfonts}
#    %%\usepackage[mathscr,mathcal]{euscript}
#    %\usepackage{txfonts}
#    %\usepackage{pxfonts}
#    %\usepackage{wasysym}
#    %\usepackage{stmaryrd}
#    \usepackage{mathdesign}

    start($ipa, qw({amssymb} {textcomp} [tone]{tipa} {tipx}));
    start($greek, qw([greek]{babel} {teubner} {pifont} {amssymb})); # amssymb is for \backepsilon and \varkappa
    start($mn, qw({MnSymbol}));
    start($ding, qw({amssymb} {pifont} {wasysym}));
    start($letters, qw({amssymb} {mathrsfs} {sansmath}));

    for (sort {$a <=> $b} keys %codes) {
        my $file = ($_ >= 0x0180 && $_ <= 0x02ff ? $ipa :
                    $_ >= 0x0370 && $_ <= 0x03ff ? $greek :
                    $_ == 0x2212 || $_ == 0x2a03 ? $mn :
                    $_ >= 0x2400 && $_ <= 0x27bf ? $ding :
                    $_ >= 0x1d400 && $_ <= 0x1d7ff ? $letters :
                    $main);

        print $file sprintf("%04x %s X{%s}X\n\n", $_, $_, $codes{$_});

# 2254 (:= not :-)        

    }

    print $_ "\\end{document}\n" for ($main, $ipa, $greek, $mn, $ding, $letters);
}

if ($COMPARE) {
    for (sort(uniq(map {0+$_}   (keys %codes),
                   map {ord $_} (keys %TeX::Encode::charmap::CHAR_MAP),
                   map {ord $_} (keys %TeXEncode::LATEX_Escapes)))) {
        $number = $_;
        my $str = chr($_);
        my $self = $codes{$number};
        my $other1 = $TeX::Encode::charmap::CHAR_MAP{$str};
        my $other2 = $TeXEncode::LATEX_Escapes{$str};
        $other1 =~ s[^\$(.*)\$$][\\ensuremath{$1}] if defined $other1;
        $other2 =~ s[^\$(.*)\$$][\\ensuremath{$1}] if defined $other2;
        if (defined $self) {
        #unless (defined $self and defined $other1 and $other1 eq $self) {
            printf("%04x %s", $number, encode_utf8(chr($number)));
            # XML is better than XML.old
            # XML is better than LATEX_Escapes when they conflict
            # XML is a superset of LATEX_Escapes
            #print(" ($other2)") if defined $other2;
            # XML is better than CHAR_MAP when they conflict
            # There are some in CHARP_MAP that are missing from XML
            #print(" ($other1)") if defined $other1;
            print(" [$self]") if defined $self;
            print("\n");
        }
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

sub latex { $codes{0+$number} = $latex; }
sub ams   { $codes{0+$number} = $ams;   }

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

#sub EndTag {
#    my ($e, $name) = @_;
#    # do something with end tags
#}
    
sub Text {
    my ($e, $data) = @_;
    s[^\s*(\S*)\s*$][$1]; # Trim whitespace

    return if $_ eq ""; # Skip if empty
    return if m[\\El] or m[\\ElsevierGlyph] or m[\\fontencoding] or m[\\cyrchar]; # Avoid these codes

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
    $mode = 'text' if m[\\texteuro];
    s[\\mathmit\b][\\mathit];

    s[^(\\.)$][$1\{\}]g; # Ensure that single macros that can take arguments already have their arguments
    s[^(\\d+dot)$][$1\{\}]g;

    s[^(\\\W){(\w)}$][$1$2]g; # translate "\'{x}" to "\'x"
    s[^(.+)$][\\ensuremath\{$1\}]
        if not m[\\ensuremath\b]
        and (defined $mode and $mode eq 'math' # Ensure math if the start tag says it's math
             or m[^\\math]); # or it is one of "\mathbf" and friends
    s[\{\{(.*?)\}\}][{$1}]g; # Remove doubled up {{x}}

    $latex = $_ if $tag eq '<latex>';
    $ams = $_ if $tag eq '<AMS>';
#    if ($tag eq '<latex>' or
#        $tag eq '<varlatex>' or
#        $tag eq '<mathlatex>' or
#        $tag eq '<AMS>' or
#        $tag eq '<IEEE>') { print " $tag $_" }
#        $tag eq '<IEEE>') { print sprintf("$tag '\\x{%04x}' => '{%s}' ", $number, $_); }

    # do something with text nodes
}
