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

my %codes;

my %decomp1;
my %decomp2;

parseUnicodeData();

#for (0x1e00 .. 0x1eff) {
#    my $x = decomp($_);
#    if (chr($_) ne $x and not grep {$x == $_} (0) {
#        printf "%04x %s %s\n", $_, encode_utf8(chr($_)), $x;
#    }
#}

#exit 1;

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
delete $codes{0x03d0}; # Wrong: \Pisymbol{ppi022}{87}


ascii();
#latin();
#latinA();
greek();
letters();


for (0x00c0 .. 0x24f, 0x1e00 .. 0x1eff) {
    my $x = decomp($_);
    #print "$_ $codes{0+$_}\n";
    if ($x ne chr($_) and $_ != 0x01ee and $_ != 0x01ef and $_ != 0x19eb) {
        $codes{$_} = $x;
    } else { delete $codes{$_}; }
}

########################################
# Taken from TeX::Encode 1.3
$codes{0x2070} = '\ensuremath{^0}';
$codes{0x2071} = '\ensuremath{^i}';
$codes{0x2074} = '\ensuremath{^4}';
$codes{0x2075} = '\ensuremath{^5}';
$codes{0x2076} = '\ensuremath{^6}';
$codes{0x2077} = '\ensuremath{^7}';
$codes{0x2078} = '\ensuremath{^8}';
$codes{0x2079} = '\ensuremath{^9}';
$codes{0x207a} = '\ensuremath{^+}';
$codes{0x207b} = '\ensuremath{^-}';
$codes{0x207c} = '\ensuremath{^=}';
$codes{0x207d} = '\ensuremath{^(}';
$codes{0x207e} = '\ensuremath{^)}';
$codes{0x207f} = '\ensuremath{^n}';
$codes{0x2080} = '\ensuremath{_0}';
$codes{0x2081} = '\ensuremath{_1}';
$codes{0x2082} = '\ensuremath{_2}';
$codes{0x2083} = '\ensuremath{_3}';
$codes{0x2084} = '\ensuremath{_4}';
$codes{0x2085} = '\ensuremath{_5}';
$codes{0x2086} = '\ensuremath{_6}';
$codes{0x2087} = '\ensuremath{_7}';
$codes{0x2088} = '\ensuremath{_8}';
$codes{0x2089} = '\ensuremath{_9}';
$codes{0x208a} = '\ensuremath{_+}';
$codes{0x208b} = '\ensuremath{_-}';
$codes{0x208c} = '\ensuremath{_=}';
$codes{0x208d} = '\ensuremath{_(}';
$codes{0x208e} = '\ensuremath{_)}';

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
    my ($main, $ipa, $greek, $mn, $ding, $letters) =
        map { IO::File->new("test/$_.tex", 'w') } qw(main ipa greek mn ding letters);

#    %\usepackage{cite}
#    %\usepackage{amsfonts}
#    %%\usepackage[mathscr,mathcal]{euscript}
#    %\usepackage{txfonts}
#    %\usepackage{pxfonts}
#    %\usepackage{wasysym}
#    %\usepackage{stmaryrd}
#    \usepackage{mathdesign}

    start($main, qw({amssymb} {amsmath} {mathrsfs} {mathabx} {shuffle} {textcomp}));
    start($ipa, qw({amssymb} {combelow} {textcomp} [tone]{tipa} {tipx})); # combelow is for \cb
    start($greek, qw({amssymb} [greek,english]{babel} {teubner})); # amssymb is for \backepsilon and \varkappa
    start($mn, qw({MnSymbol}));
    start($ding, qw({amssymb} {pifont} {wasysym}));
    start($letters, qw({amsmath} {amssymb} {bbold} {mathrsfs} {sansmath}));

    print $ipa "\\newcommand{\\C}{\\textdoublegrave}\n";
    print $ipa "\\newcommand{\\f}{\\textroundcap}\n";
    print $ipa "\\newcommand{\\D}{\\textsubring}\n";
    print $ipa "\\newcommand{\\V}{\\textsubcircum}\n";
    print $ipa "\\newcommand{\\T}{\\textsubtilde}\n";
#textsubbreve

    for (sort {$a <=> $b} keys %codes) {
        my $file = ($_ >= 0x0370 && $_ <= 0x03ff ? $greek :
                    $_ >= 0x0100 && $_ <= 0x1fff ? $ipa : # General scripts area
                    $_ >= 0x2c00 && $_ <= 0x2dff ? $ipa : # General scripts area
                    # 2000-2bff, 2e00-2e7f # Symbols and punctuation
                    # 3000-3030 # CJK punctuation
                    $_ == 0x2212 || $_ == 0x2a03 ? $mn :
                    $_ >= 0x2400 && $_ <= 0x27bf ? $ding :
                    $_ >= 0x1d400 && $_ <= 0x1d7ff ? $letters :
                    $main);

        print $file sprintf("%04x X{%s}X\n\n", $_, $codes{$_});

# TODO: 0x2254 (:= not :-)        
# TODO: 0x2afg (has extra {})

    }

    print $_ "\\end{document}\n" for ($main, $ipa, $greek, $mn, $ding, $letters);
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
        if (defined $other1) {
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

    s[^(\\.)$][$1\{\}]g; # Ensure that single macros that can take arguments already have their arguments
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

sub greek {
#0   1    2    3    4    5    6    7    8    9    A    B    C    D    E    F
    my @letters = qw(
_    _    _    _    _    _    _    _    _    _    _    _    _    _    _    _    
_    _    _    _    '    "'   'A   _    'E   'H   'I   _    'O   _    'Y   'W    
"'i  A    B    G    D    E    Z    H    J    I    K    L    M    N    X    O    
P    R    _    S    T    U    F    Q    Y    W    "I   "U   'a   'e   'h   'i   
"'u  a    b    g    d    e    z    h    j    i    k    l    m    n    x    o    
p    r    c    s    t    u    f    q    y    w    "i   "u   'o   'u   'w   _

_                      \ensuremath{\vartheta} _                     _
"\ensuremath{\Upsilon} \ensuremath{\phi}      \ensuremath{\varpi}   _
\Koppa                 \coppa                 \Stigma               \stigma
\Digamma               \digamma               _                     \koppa

\Sampi                 \sampi                 _                     _
_                      _                      _                     _
_                      _                      _                     _
_                      _                      _                     _

\ensuremath{\varkappa} \ensuremath{\varrho}   _                     _
\ensuremath{\Theta}    \ensuremath{\epsilon}  \ensuremath{\backepsilon} _
_                      _                      _                     _
_                      _                      _                     _
);
    for my $i (0 .. $#letters) {
        if ($letters[$i] =~ /^_$/) { delete $codes{0x0370 + $i} }
        else {
            $codes{0x0370 + $i} = ($letters[$i] =~ /^\\ensuremath/ ?
                                   $letters[$i] : "\\textgreek{$letters[$i]}");
        }
    }
}

sub letters {
    my $char = 0x1d400;
    my @latin = map {chr($_)} (0x41 .. 0x5a, 0x61 .. 0x7a);
    my @greek = qw(A B \Gamma \Delta E Z H \Theta I K \Lambda M N \Xi
                   O \Pi R \varTheta \Sigma T \Upsilon \Phi X \Psi \Omega \nabla
                   \alpha \beta \gamma \delta \varepsilon \zeta \eta
                   \theta \iota \kappa \lambda \mu \nu \xi o \pi \rho
                   \varsigma \sigma \tau \upsilon \varphi \chi \psi \omega
                   \partial \varepsilon \vartheta \varkappa \phi \varrho \varpi);
    my @digits = qw(0 1 2 3 4 5 6 7 8 9);

    for my $tex (qw(\ensuremath{\mathbf{_}}
                    \ensuremath{\mathit{_}}
                    \ensuremath{\boldsymbol{_}}
                    \ensuremath{\mathscr{_}}
                    \ensuremath{\mathbfscr{_}}
                    \ensuremath{\mathfrak{_}}
                    \ensuremath{\mathbb{_}}
                    \ensuremath{\mathbffrak{_}}
                    \ensuremath{\mathsf{_}}
                    \ensuremath{\mathsfbf{_}}
                    \ensuremath{\mathsfsl{_}}
                    \ensuremath{\mathsfbfsl{_}}
                    \ensuremath{\mathtt{_}}
                   )) {
        for (@latin) {
            ($codes{$char++} = $tex) =~ s/_/$_/g;
        }
    }

    $codes{$char++} = qw(\ensuremath{\imath});
    $codes{$char++} = qw(\ensuremath{\jmath});
    delete $codes{$char++}; # Reserved
    delete $codes{$char++}; # Reserved

    for my $tex (qw(\ensuremath{\mathbf{_}}
                    \ensuremath{\mathit{_}}
                    \ensuremath{\boldsymbol{_}}
                    \ensuremath{\mathsf{_}}
                    \ensuremath{\mathsfbfsl{_}}
                   )) {
        for (@greek) {
            ($codes{$char++} = $tex) =~ s/_/$_/g;
        }
    }

    $codes{$char++} = qw(\ensuremath{\mathbf{\digamma}});
    delete $codes{$char++}; # Small digamma
    delete $codes{$char++}; # Reserved
    delete $codes{$char++}; # Reserved

    for my $tex (qw(\textbf{_}
                    \textbb{_}
                    \textsf{_}
                    \textsf{\textbf{_}}
                    \texttt{_}
                   )) {
        for (@digits) {
            ($codes{$char++} = $tex) =~ s/_/$_/g;
        }
    }
}

sub ding {

#    2423 X{\textvisiblespace}X;
#
#    2460 \ding{172} (1..9)
#    2468
#
#        24B6 \textcircled{A} .. Z a .. z
#
#    2500 .. 259f pmboxdraw



}

sub set_codes {
    my ($char, @codes) = @_;
    for (@codes) {
        if ($_ eq '_') { delete $codes{$char} }
        else { $codes{$char} = $_ }
        $char++;
    }
}

sub ascii {
# Taken from Table 328 of "The Comprehensive LaTeX Symbol List"
    set_codes(0x22, qw(\textquotedbl \# \$ \% \&));
    set_codes(0x3c, qw(\textless _ \textgreater));
    set_codes(0x5c, qw(\textbackslash));
    set_codes(0x5e, qw(\^{}));
    set_codes(0x5f, qw(\_));
    set_codes(0x7b, qw(\{));
    #set_codes(0x7c, qw(\textbar));
    set_codes(0x7e, qw(\}));
    set_codes(0x7f, qw(\~{}));

}

sub latin1 {
# Taken from Table 329 of "The Comprehensive LaTeX Symbol List"
    set_codes(0xa0, qw(
~
!`
\textcent
\pounds
\textcurrency
\textyen
\textbrokenbar
\S
\textasciidieresis
\textcopyright
\textordfeminine
\guillemotleft
\textlnot
\-
\textregistered
\textasciimacron

\textdegree
\textpm
\texttwosuperior
\textthreesuperior
\textasciiacute
\textmu
\P
\textperiodcentered
\c{}
\textonesuperior
\textordmasculine
\guillemotright
\textonequarter
\textonehalf
\textthreequarters
?`

\`{A}
\'{A}
\^{A}
\~{A}
\"{A}
\AA
\AE
\c{C}
\`{E}
\'{E}
\^{E}
\"{E}
\`{I}
\'{I}
\^{I}
\"{I}

\DH
\~{N}
\`{O}
\'{O}
\^{O}
\~{O}
\"{O}
\texttimes
\O
\`{U}
\'{U}
\^{U}
\"{U}
\'{Y}
\TH
\ss

\`{a}
\'{a}
\^{a}
\~{a}
\"{a}
\aa
\ae
\c{c}
\`{e}
\'{e}
\^{e}
\"{e}
\`{i}
\'{i}
\^{i}
\"{i}

\dh
\~{n}
\`{o}
\'{o}
\^{o}
\~{o}
\"{o}
\textdiv
\o
\`{u}
\'{u}
\^{u}
\"{u}
\'{y}
\th
\"{y}
));
}

sub parseUnicodeData {
    my $fh = IO::File->new("UnicodeData.txt", 'r');
    while (<$fh>) {
        my ($code, $dummy, $decomp1, $decomp2) = m/^([0-9A-F]+);([^;]*;){4}([0-9A-F]+) ([0-9A-F]+);/;
        if (defined $decomp2) {
            #print $_, "\n";
            #printf "%04x %04x %04x\n", hex($code), hex($decomp1), hex($decomp2);
            $decomp1{hex($code)} = hex($decomp1);
            $decomp2{hex($code)} = hex($decomp2);
        }
    }
}

sub decomp {
    my ($char) = @_;

    #printf "char=%04x\n", $char;

    my @accents = qw(
`  '  ^  ~  =  __ u  .
"  h  r  H  v  |  U  G

__ textroundcap __ __ __ __ __ __
__ __ __ __ __ __ __ __

__ __ __ d  textsubumlaut textsubring   cb c 
k  __ __ __ __            textsubcircum textsubbreve __

textsubtilde b  __ __ __ __ __ __
__ __ __ __ __ __ __ __
);

# 17f .. 1cc
    my %special = (
        0x00c5, '\AA',
        0x00c6, '\AE',
        0x00d0, '\DH',
        0x00d7, '\texttimes',
        0x00d8, '\O',
        0x00de, '\TH',
        0x00df, '\ss',
        0x00e5, '\aa',
        0x00e6, '\ae',
        0x00f0, '\dh',
        0x00f7, '\textdiv',
        0x00f8, '\o',
        0x00fe, '\th',

        0x0110, '\DJ',
        0x0111, '\dj',
        0x0131, '\i',
        0x0132, '\IJ',
        0x0133, '\ij',
        0x0141, '\L',
        0x0142, '\l',
        0x0149, '\'n',
        0x014a, '\NG',
        0x014b, '\ng',
        0x0152, '\OE',
        0x0153, '\oe',
        0x01a0, '\OHORN',
        0x01a1, '\ohorn',
        0x01af, '\UHORN',
        0x01b0, '\uhorn',
        );

    if (exists $special{$char}) {
        return $special{$char};
    } elsif (exists $decomp2{$char}) {
        return "\\$accents[$decomp2{$char}-0x300]\{" . decomp($decomp1{$char}) . "}";
    } else { return chr($char); }
}
