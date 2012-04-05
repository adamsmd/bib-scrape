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

my ($TEST_TEX, $COMPARE, $MAKE_MODULE) = (0, 1, 0);

my @accents = qw(
`  '  ^  ~  =  __ u  .
"  h  r  H  v  |  U  G

__ textroundcap __ __ __ __ __ __
__ __ __ __ __ __ __ __

__ __ __ d  textsubumlaut textsubring   cb           c 
k  __ __ __ __            textsubcircum textsubbreve __

textsubtilde b  __ __ __ __ __ __
__ __ __ __ __ __ __ __

__ __ __ __ __ __ __ __
__ __ __ __ __ __ __ __

__ __ __ __ __ __ __ __
__ __ __ __ __ __ __ __

__ __ __ __ __ __ __ __
__ __ __ __ __ __ __ __
);

my %codes;

my %decomp1;
my %decomp2;

parseUnicodeData();

#my $p = XML::Parser->new(Style => 'Stream', Pkg => 'main');
#$p->parsefile('-');

$codes{0x00ad} = '\-'; # Don't want extra {} at the end
$codes{0x0192} = '\textflorin'; # Wrong: \ensuremath{f}
$codes{0x0195} = '\texthvlig'; # Missing
$codes{0x019e} = '\textnrleg'; # Missing
#$codes{0x01aa} = '\ensuremath{\eth}'; # Wrong
$codes{0x01c2} = '\textdoublepipe'; # Missing
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
delete $codes{0x03d0}; # Wrong: \Pisymbol{ppi022}{87}

ascii();
latin1();
greek();
letters();
ding();
shapes();
other();

for (0x0300 .. 0x036f) {
    set_codes($_, ($accents[$_-0x300] ne '__' ?
                   "\\$accents[$_-0x300]\{\}" : '_'));
}

# \i
for (0x00c0 .. 0x24f, 0x1e00 .. 0x1eff) {
    my $x = decomp($_);
    #print "$_ $codes{0+$_}\n";
    if ($x ne chr($_) and $_ != 0x01ee and $_ != 0x01ef and $_ != 0x1e9b) {
        $codes{$_} = $x;
    } else { delete $codes{$_}; }
}

for (0x1f00 .. 0x1fff) {
    my $x = greekDecomp($_);
    if ($x ne 'RES' and $x ne 'TODO') {
        $codes{$_} = $x;
    } else { delete $codes{$_} }
}

# Super and subscripts
set_codes(0x2070,
          (map { "\\textsuperscript{$_}" } qw[0 i]),
          qw[_ _],
          (map { "\\textsuperscript{$_}" } qw[4 5 6 7 8 9 + - = ( ) n]),
          (map { "\\textsubscript{$_}" } qw[0 1 2 3 4 5 6 7 8 9 + - = ( )]),
          qw[_],
          (map { "\\textsubscript{$_}" } qw[a e o x \textschwa h k l m n p s t]));


## IPA extensions
#025b X{\ensuremath{\varepsilon}}X
#
#0261 X{g}X
#
#0278 X{\ensuremath{\phi}}X
#
#029e X{\textturnk}X
#
## Spacing modifiers
#
#02bc X{\rasp}X
#
#02c6 X{\^{}}X
#
#02c7 X{\textasciicaron}X
#
#02d8 X{\textasciibreve}X
#
#02d9 X{\textperiodcentered}X
#
#02da X{\r{}}X
#
#02db X{\k{}}X
#
#02dc X{\~{}}X
#
#02dd X{\H{}}X
#
#02e5 X{\tone{55}}X
#
#02e6 X{\tone{44}}X
#
#02e7 X{\tone{33}}X
#
#02e8 X{\tone{22}}X
#
#02e9 X{\tone{11}}X
#

for my $key (keys %codes) {
    $_ = $codes{$key};
    cleanCode();
    $codes{$key} = $_;
}

sub start {
    my ($file, @packages) = @_;
    print $file "\\documentclass[11pt]{article}\n\\usepackage[T1]{fontenc}\n";
    print $file "\\usepackage$_\n" for @packages;
    print $file "\\begin{document}\n\n";
}

if ($TEST_TEX) {
    my ($latin, $main, $greek, $mn, $ding, $letters) =
        map { IO::File->new("test/$_.tex", 'w') } qw(latin main greek mn ding letters);

#    %\usepackage{cite}
#    %\usepackage{amsfonts}
#    %%\usepackage[mathscr,mathcal]{euscript}
#    %\usepackage{txfonts}
#    %\usepackage{pxfonts}
#    %\usepackage{wasysym}
#    %\usepackage{stmaryrd}
#    \usepackage{mathdesign}

    start($latin, qw({textcomp} {tipx}));
    start($main, qw({amssymb} {amsmath} {fixltx2e} {mathrsfs} {mathabx} {shuffle} {textcomp} {tipa}));
#\usepackage{amssymb}
#\usepackage{amsmath}
#\usepackage{textcomp}
#\usepackage{stmaryrd}
#\usepackage{xfrac}
#\usepackage{txfonts}
#\usepackage{mathdots}
#\usepackage{wasysym}
#% \usepackage{mathabx} Causes conflicts
#\usepackage{mathbbol}
#\usepackage{shuffle}

    start($greek, qw({amssymb} [greek,english]{babel} {teubner})); # amssymb is for \backepsilon and \varkappa
    start($mn, qw({MnSymbol}));
    start($ding, qw({amssymb} {amsmath} {pifont} {pxfonts} {skak} {wasysym} {xfrac}));
    start($letters, qw({amsmath} {amssymb} {bbold} {mathrsfs} {sansmath}));

    print $latin "\\renewcommand{\\|}{} % \\usepackage{fc}\n";
    print $latin "\\newcommand{\\G}{} % \\usepackage{fc}\n";
    print $latin "\\newcommand{\\U}{} % \\usepackage{fc}\n";
    print $latin "\\newcommand{\\h}{} % \\usepackage{vntex}\n";
    print $latin "\\newcommand{\\OHORN}{} % \\usepackage{vntex}\n";
    print $latin "\\newcommand{\\ohorn}{} % \\usepackage{vntex}\n";
    print $latin "\\newcommand{\\UHORN}{} % \\usepackage{vntex}\n";
    print $latin "\\newcommand{\\uhorn}{} % \\usepackage{vntex}\n";
    print $latin "\\newcommand{\\textsubbreve}{} % DOES NOT EXIST\n";
    print $latin "\\newcommand{\\cb}{} % \\usepackage{combelow}\n";

    for (sort {$a <=> $b} keys %codes) {
        my $file = (
            $_ >= 0x0000 && $_ <= 0x036f ? $latin :
              #  0000.. 007f ascii
              #  0080.. 009f [omitted: control]
              #  00a0.. 00bf latin1
              #  00c0.. 024f decomp
              #  0250.. 02ff [omitted: ipa]
              #  0300.. 036f accents
            $_ >= 0x0370 && $_ <= 0x03ff ? $greek :
              #  0370.. 03ff greek
            $_ >= 0x0400 && $_ <= 0x01df ? undef :
              #  0400.. 1dff [omitted: hebrew, arabic, etc.]
            $_ >= 0x1e00 && $_ <= 0x1eff ? $latin :
              #  1e00.. 1eff decomp
            $_ >= 0x1f00 && $_ <= 0x1fff ? $greek :
              #  1f00.. 1fff greek decomp
            #  2000.. ffff (???)
            #   2400.. 27bf ding
            #     2400 control
            #     2460 digits
            #     2500 box drawing
            #     25a0 shapes
            #     2600 misc
            #     2700 ding
            #       33 -> 01..60 [05,0A,0B,28,4c,4e,53,54,55,57,5f,60,68-75,95,96,97,b0,bf]
            #             13 [\checkmark]
#
            #       
            #   301a.. 301b open brackets
            #   fb00.. fb04 *ffil
            $_ >=0x1d400 && $_ <=0x1d7ff ? $letters :
              # 1d400..1d7ff letters

            # 2000-2bff, 2e00-2e7f # Symbols and punctuation
            # 3000-3030 # CJK punctuation
            #$_ == 0x2212 || $_ == 0x2a03 ? $mn :
            $_ >= 0x2400 && $_ <= 0x27bf ? $ding :
            $main);

        print $file sprintf("%04x X{%s}X\n\n", $_, $codes{$_});

# TODO: 0x2254 (:= not :-)        
# TODO: 0x2afg (has extra {})

    }

    print $_ "\\end{document}\n" for ($latin, $main, $greek, $mn, $ding, $letters);
}

if ($COMPARE) {
    for (sort {$a <=> $b}
             (uniq(map {0+$_}   (keys %codes),
                   map {ord $_} (keys %TeX::Encode::charmap::CHAR_MAP),
                   map {ord $_} (keys %TeXEncode::LATEX_Escapes)))) {
        $number = $_;
        my $str = chr($_);
        my $self = $codes{$number};
        my $other1 = $TeX::Encode::charmap::CHAR_MAP{$str};
        my $other2 = $TeXEncode::LATEX_Escapes{$str};
        $other1 =~ s[^\$(.*)\$$][\\ensuremath{$1}] if defined $other1;
        $other2 =~ s[^\$(.*)\$$][\\ensuremath{$1}] if defined $other2;
        unless (defined $self and defined $other1 and $other1 eq $self) {
            printf("%04x %s", $number, encode_utf8(chr($number)));
            # XML is better than XML.old
            # XML is better than LATEX_Escapes when they conflict
            # XML is a superset of LATEX_Escapes
            #print(" ($other2)") if defined $other2;
            # XML is better than CHAR_MAP when they conflict
            # There are some in CHARP_MAP that are missing from XML
            print(" ($other1)") if defined $other1;
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
