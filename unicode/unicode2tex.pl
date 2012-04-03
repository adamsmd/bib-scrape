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

$codes{0xfb00} = 'ff';
$codes{0xfb01} = 'fi';
$codes{0xfb02} = 'fl';
$codes{0xfb03} = 'ffi';
$codes{0xfb04} = 'ffl';

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

sub greekDecomp {
    my ($char) = @_;

    if (grep { $char - 0x1f00 == hex($_) }
        qw(16 17 1e 1f 46 47 4e 4f 58 5a 5c 5e 7e 7f b5 c5 d4 d5 dc f0 f1 f5 ff)) {
        return "RES";
    } elsif ($char == 0x1fc0 or $char == 0x1fc1 or
        $char == 0x1fbd or $char == 0x1fbe or $char == 0x1fbf or
        $char == 0x1fcd or $char == 0x1fce or $char == 0x1fcf or
        $char == 0x1fdd or $char == 0x1fde or $char == 0x1fdf or
        $char == 0x1fed or $char == 0x1fee or $char == 0x1fef or
        $char == 0x1ffd or $char == 0x1ffe) {
        return "TODO";
    } elsif (0x0370 <= $char && $char <= 0x03ff) {
        return $codes{$char};
    } elsif (exists $decomp2{$char}) {
        my $x = greekDecomp($decomp1{$char});
        if ($decomp2{$char} == 0x0300 and $x =~ m[^\\textgreek{(.*)}$]) {
            return "\\textgreek{`$1}";
        } elsif ($decomp2{$char} == 0x0301 and $x =~ m[^\\textgreek{(.*)}$]) {
            return "\\textgreek{'$1}";
        } elsif ($decomp2{$char} == 0x0304 and $x =~ m[^\\textgreek{(.*)}$]) {
            return "\\textgreek{\\={$1}}";
        } elsif ($decomp2{$char} == 0x0306 and $x =~ m[^\\textgreek{(.*)}$]) {
            return "\\textgreek{\\u{$1}}";
        } elsif ($decomp2{$char} == 0x0308 and $x =~ m[^\\textgreek{(.*)}$]) {
            return "\\textgreek{\"$1}";
        } elsif ($decomp2{$char} == 0x0313 and $x =~ m[^\\textgreek{(.*)}$]) {
            return "\\textgreek{>$1}";
        } elsif ($decomp2{$char} == 0x0314 and $x =~ m[^\\textgreek{(.*)}$]) {
            return "\\textgreek{<$1}";
        } elsif ($decomp2{$char} == 0x0342 and $x =~ m[^\\textgreek{(.*)}$]) {
            return "\\textgreek{~$1}";
        } elsif ($decomp2{$char} == 0x0345 and $x =~ m[^\\textgreek{(.*)}$]) {
            return "\\textgreek{$1|}";
        } else {
            printf "ERROR: %04x %04x %04x %s\n", $char, $decomp1{$char}, $decomp2{$char}, $x;
            exit 1;
        }
    } elsif (exists $decomp1{$char}) { return greekDecomp($decomp1{$char});
    } else {
        printf "ERROR: %04x %04x %04x\n", $char, $decomp1{$char}, $decomp2{$char};
        return "_";
    }
    
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

    set_codes(0x2423, qw(\textvisiblespace));
#    2460 \ding{172} (1..9)
    for my $char (0x2460 .. 0x2469) {
        set_codes($char, "\\ding{" . (172 - 0x2460 + $char) . "}");
    }

    for my $char (0x24b6 .. 0x24cf) {
        set_codes($char, "\\textcircled{" . chr(ord('A') - 0x24b6 + $char) . "}");
    }
    for my $char (0x24d0 .. 0x24e9) {
        set_codes($char, "\\textcircled{" . chr(ord('a') - 0x24d0 + $char) . "}");
    }
    set_codes(0x24ea, "\\textcircled{0}");
    set_codes(0x24c5, "\\textcircledP");
    set_codes(0x24c7, "\\circledR");

# TODO: 2500 .. 259f pmboxdraw
# TODO: 25a0 .. box drawing

    my %alt = map { hex($_) } qw(2700 0000
                                 2705 260e
                                 270a 261b
                                 270b 261e
                                 2728 2605
                                 274c 25cf
                                 274e 25a0
                                 2753 25b2
                                 2754 25bc
                                 2755 25c6
                                 2757 25d7
                                 275f 0000
                                 2760 0000
                                 2768 0000
                                 2769 2666
                                 276a 2665
                                 276b 0000
                                 276c 0000
                                 276d 0000
                                 276e 0000
                                 276f 0000
                                 2770 0000
                                 2771 0000
                                 2772 0000
                                 2773 0000
                                 2774 0000
                                 2775 0000
                                 2795 2192
                                 2796 2194
                                 2797 2195
                                 27b0 0000
                                 27bf 0000);
        
# NOTE: Unicode 6.0 fails to list 25d7, 2665 and 2666

    for my $char (0x2700 .. 0x27bf) {
        if (exists $alt{$char}) {
            set_codes($char, '_');
            set_codes($alt{$char},
                      ($alt{$char} == 0 ? '_' :
                       $char >= 0x2760 ?
                       "\\ding{" . (160 - 0x2760 + $char) . "}" :
                       "\\ding{" . (32 - 0x2700 + $char) . "}"));
        } else {
            if ($char >= 0x2760) {
                set_codes($char, "\\ding{" . (160 - 0x2760 + $char) . "}");
            } else {
                set_codes($char, "\\ding{" . (32 - 0x2700 + $char) . "}");
            }
        }
    }
}

sub shapes {
    set_codes(0x25a0, qw(\ensuremath{\blacksquare} \ensuremath{\square}));
    set_codes(0x25b2, qw(\ensuremath{\blacktriangle} \ensuremath{\vartriangle}));
    set_codes(0x25b6, qw(\ensuremath{\blacktriangleright} \ensuremath{\vartriangleright})); #RHD \rhd));
    set_codes(0x25bc, qw(\ensuremath{\blacktriangledown} \ensuremath{\triangledown}));
    set_codes(0x25c0, qw(\ensuremath{\blacktriangleleft} \ensuremath{\vartriangleright})); #\LHD \lhd));
    set_codes(0x25ca, qw(\ensuremath{\lozenge}));
    set_codes(0x25e6, qw(\textopenbullet));
    set_codes(0x25cf, qw(\CIRCLE \LEFTcircle \RIGHTcircle));
    set_codes(0x25d6, qw(\LEFTCIRCLE \RIGHTCIRCLE));
    set_codes(0x25ef, qw(\textbigcircle));


    set_codes(0x2605, qw(\ensuremath{\bigstar}));
    set_codes(0x2609, qw(\astrosun));
    set_codes(0x2639, qw(\frownie \smiley \blacksmiley \sun));
    set_codes(0x263d, qw(\rightmoon \leftmoon));
    set_codes(0x263f, qw(\mercury \venus \earth \mars \jupiter \saturn _ \neptune \pluto));
    set_codes(0x2648, qw(\aries \taurus \gemini \cancer \leo \virgo \libra
                         \scorpio \sagittarius \capricornus \aquarius \pisces));
    set_codes(0x2654, qw(\symking \symqueen \symrook \symbishop \symknight \sympawn));
    set_codes(0x2660, qw(\ensuremath{\spadesuit} \ensuremath{\heartsuit}
                         \ensuremath{\diamondsuit} \ensuremath{\clubsuit}
                         \ensuremath{\varspadesuit} \ensuremath{\varheartsuit}
                         \ensuremath{\vardiamondsuit} \ensuremath{\varclubsuit}));

    set_codes(0x2669, qw(\quarternote \eighthnote \twonotes _
                         \ensuremath{\flat} \ensuremath{\natural} \ensuremath{\sharp}));
    set_codes(0x26e2, qw(\uranus));
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
));
}

sub parseUnicodeData {
    my $fh = IO::File->new("UnicodeData.txt", 'r');
    while (<$fh>) {
        my ($code, $dummy, $decomp1, $dummy2, $decomp2) = m/^([0-9A-F]+);([^;]*;){4}([0-9A-F]+)( ([0-9A-F]+))?;/;
        if (defined $decomp2) {
            #print $_, "\n";
            #printf "%04x %04x %04x\n", hex($code), hex($decomp1), hex($decomp2);
            $decomp2{hex($code)} = hex($decomp2);
        }
        if (defined $decomp1) {
            $decomp1{hex($code)} = hex($decomp1);
        }
    }
}

sub decomp {
    my ($char) = @_;

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
    } elsif (exists $codes{$char}) {
        return $codes{$char};
    } else { return chr($char); }
}

sub other {

# General Punctuation
    set_codes(0x2000, qw(
\enskip \quad \enspace \quad
\thickspace \medspace \hspace{0.166em} \hphantom{0}
\hphantom{.} \thinspace \ensuremath{\mkern1mu} \hspace{0em}
_ _ _ _

- \mbox{-} _ --
--- --- \ensuremath{\Vert} _
\textquoteleft \textquoteright \quotesinglbase _
\textquotedblleft \textquotedblright \quotedblbase _

\dag \ddag \textbullet _
. .. \ldots \textperiodcentered
\\\\ \par _ _
_ _ _ _

\textperthousand \textpertenthousand \ensuremath{^{\prime}} \ensuremath{^{\prime\prime}}
\ensuremath{^{\prime\prime\prime}} \ensuremath{^{\backprime}} \ensuremath{^{\backprime\backprime}} \ensuremath{^{\backprime\backprime\backprime}}
_ \guilsinglleft \guilsinglright \textreferencemark
{!!} \textinterrobang _ _
));

    set_codes(0x2050, qw(
_ _ _ _
_ _ _ \ensuremath{^{\prime\prime\prime\prime}}
_ _ _ _
_ _ _ \ensuremath{\mkern4mu}

{} _ _ _));

# Currency Symbols
    set_codes(0x20a0, qw(
_ \textcolonmonetary _ _
  \textlira _ \textnaira _
_ \textwon  _ \textdong
\texteuro _ _ _

_ \textpeso \textguarani _
));

# 20db \ensuremath{\dddot{}}
# 20dc \ensuremath{\ddddot{}}
# 23bd \obar
# 23b0 \lmoustache
# 2571 \diagup
# \textblank

#\def\mathscr{}
#\def\Pfund{}
#\def\fax{}

# Combining diacriticals for symbols
    set_codes(0x2100, qw(
_ _ \ensuremath{\mathbb{C}} \textcelsius
_ _ _ _
_ \textdegree{}F \ensuremath{\mathscr{g}} \ensuremath{\mathscr{H}}
\ensuremath{\mathfrak{H}} \ensuremath{\mathbb{H}} \ensuremath{h} \ensuremath{\hslash}

\ensuremath{\mathscr{I}} \ensuremath{\Im} \ensuremath{\mathscr{L}} \ensuremath{\ell}
\Pfund \ensuremath{\mathbb{N}} \textnumero \textcircledP
\ensuremath{\wp} \ensuremath{\mathbb{P}} \ensuremath{\mathbb{Q}} \ensuremath{\mathscr{R}}
\ensuremath{\Re} \ensuremath{\mathbb{R}} \textrecipe _

\textservicemark _ \texttrademark _
\ensuremath{\mathbb{Z}} _ \textohm \textmho
\ensuremath{\mathfrak{Z}} _ K \AA
\ensuremath{\mathscr{B}} \ensuremath{\mathfrak{C}} \textestimated \ensuremath{\mathscr{e}}

\ensuremath{\mathscr{E}} \ensuremath{\mathscr{F}} _ \ensuremath{\mathscr{M}}
\ensuremath{\mathscr{o}} \ensuremath{\aleph} \ensuremath{\beth} \ensuremath{\gimel}
\ensuremath{\daleth} _ _ \fax
\ensuremath{\mathbb{\pi}} \ensuremath{\mathbb{\gamma}} \ensuremath{\mathbb{\Gamma}} \ensuremath{\mathbb{\Pi}}

\ensuremath{\mathbb{\sum}} \ensuremath{\Game} _ _
_ \ensuremath{\mathbb{D}} \ensuremath{\mathbb{d}} \ensuremath{\mathbb{e}}
\ensuremath{\mathbb{i}} \ensuremath{\mathbb{j}} _ _
));

# Number forms
    set_codes(0x2150, qw(
\sfrac{1}{7} \sfrac{1}{9} \sfrac{1}{10} \sfrac{1}{3}
\sfrac{2}{3} \sfrac{1}{5} \sfrac{2}{5} \sfrac{3}{5}
\sfrac{4}{5} \sfrac{1}{6} \sfrac{5}{6} \sfrac{1}{8}
\sfrac{3}{8} \sfrac{5}{8} \sfrac{7}{8} \sfrac{1}{}

I II III IV V VI VII VIII IX X XI XII L C D M

i ii iii iv v vi vii viii ix x xi xii l c d m
));
    set_codes(0x2189, qw(\sfrac{0}{3}));

# Arrows
    set_codes(0x2190, qw(
\ensuremath{\leftarrow} \ensuremath{\uparrow} \ensuremath{\rightarrow} \ensuremath{\downarrow}
\ensuremath{\leftrightarrow} \ensuremath{\updownarrow} \ensuremath{\nwarrow} \ensuremath{\nearrow}
\ensuremath{\searrow} \ensuremath{\swarrow} \ensuremath{\nleftarrow} \ensuremath{\nrightarrow} 
_ _ \ensuremath{\twoheadleftarrow} _

\ensuremath{\twoheadrightarrow} _ \ensuremath{\leftarrowtail} \ensuremath{\rightarrowtail}
\ensuremath{\mapsfrom} _ \ensuremath{\mapsto} _
_ \ensuremath{\hookleftarrow} \ensuremath{\hookrightarrow} \ensuremath{\looparrowleft}
\ensuremath{\looparrowright} \ensuremath{\leftrightsquigarrow} \ensuremath{\nleftrightarrow} \ensuremath{\lightning}

\ensuremath{\Lsh} \ensuremath{\Rsh} _ _
_ _ \ensuremath{\curvearrowleft} \ensuremath{\curvearrowright}
_ _ \ensuremath{\circlearrowleft} \ensuremath{\circlearrowright}
\ensuremath{\leftharpoonup} \ensuremath{\leftharpoondown} \ensuremath{\upharpoonright} \ensuremath{\upharpoonleft}

\ensuremath{\rightharpoonup} \ensuremath{\rightharpoondown} \ensuremath{\downharpoonright} \ensuremath{\downharpoonleft}
\ensuremath{\rightleftarrows} _ \ensuremath{\leftrightarrows} \ensuremath{\leftleftarrows}
\ensuremath{\upuparrows} \ensuremath{\rightrightarrows} \ensuremath{\downdownarrows} \ensuremath{\leftrightharpoons}
\ensuremath{\rightleftharpoons} \ensuremath{\nLeftarrow} \ensuremath{\nLeftrightarrow} \ensuremath{\nRightarrow}

\ensuremath{\Leftarrow} \ensuremath{\Uparrow} \ensuremath{\Rightarrow} \ensuremath{\Downarrow}
\ensuremath{\Leftrightarrow} \ensuremath{\Updownarrow} \ensuremath{\Nwarrow} \ensuremath{\Nearrow}
\ensuremath{\Searrow} \ensuremath{\Swarrow} \ensuremath{\Lleftarrow} \ensuremath{\Rrightarrow}
\ensuremath{\leftsquigarrow} \ensuremath{\rightsquigarrow} _ _

\ensuremath{\dashleftarrow} \ensuremath{\dashrightarrow} _ _
));
    set_codes(0x21fc, qw(
_ \ensuremath{\leftarrowtriangle} \ensuremath{\rightarrowtriangle} \ensuremath{\leftrightarrowtriangle}));

# Math operators
    set_codes(0x2200, qw(
\ensuremath{\forall} \ensuremath{\complement} \ensuremath{\partial} \ensuremath{\exists}
\ensuremath{\nexists} \ensuremath{\varnothing} \ensuremath{\Delta} \ensuremath{\nabla}
\ensuremath{\in} \ensuremath{\notin} _ \ensuremath{\ni}
\ensuremath{\notni} _ \ensuremath{\Box} \ensuremath{\prod}

\ensuremath{\coprod} \ensuremath{\sum} \ensuremath{-} \ensuremath{\mp}
\ensuremath{\dotplus} \ensuremath{/} \ensuremath{\setminus} \ensuremath{\ast}
\ensuremath{\circ} \ensuremath{\bullet} \ensuremath{\surd} \ensuremath{\sqrt[3]{}}
\ensuremath{\sqrt[4]{}} \ensuremath{\propto} \ensuremath{\infty} _

\ensuremath{\angle} \ensuremath{\measuredangle} \ensuremath{\sphericalangle} \ensuremath{\mid}
\ensuremath{\nmid} \ensuremath{\parallel} \ensuremath{\nparallel} \ensuremath{\wedge}
\ensuremath{\vee} \ensuremath{\cap} \ensuremath{\cup} \ensuremath{\int}
\ensuremath{\iint} \ensuremath{\iiint} \ensuremath{\oint} \ensuremath{\oiint}

\ensuremath{\oiiint} _ \ensuremath{\ointclockwise} \ensuremath{\ointctrclockwise}
\ensuremath{\therefore} \ensuremath{\because} \ensuremath{\mathrel{:}} \ensuremath{\mathrel{::}}
\ensuremath{\dot{-}} \ensuremath{\eqcolon} _ _
\ensuremath{\sim} \ensuremath{\backsim} _ _

\ensuremath{\wr} \ensuremath{\nsim} \ensuremath{\eqsim} \ensuremath{\simeq}
\ensuremath{\nsimeq} \ensuremath{\cong} _ \ensuremath{\ncong}
\ensuremath{\approx} \ensuremath{\napprox} \ensuremath{\approxeq} _
_ \ensuremath{\asymp} \ensuremath{\Bumpeq} \ensuremath{\bumpeq}

\ensuremath{\doteq} \ensuremath{\doteqdot} \ensuremath{\fallingdotseq} \ensuremath{\risingdotseq}
\ensuremath{\coloneq} \ensuremath{\eqcolon} \ensuremath{\eqcirc} \ensuremath{\circeq}
_ _ _ _
\ensuremath{\triangleq} _ _ _

\ensuremath{\ne} \ensuremath{\equiv} \ensuremath{\nequiv} _
\ensuremath{\leq} \ensuremath{\geq} \ensuremath{\leqq} \ensuremath{\geqq}
\ensuremath{\lneqq} \ensuremath{\gneqq} \ensuremath{\ll} \ensuremath{\gg}
\ensuremath{\between} \ensuremath{\not\asymp} \ensuremath{\nless} \ensuremath{\ngtr}

\ensuremath{\nleq} \ensuremath{\ngeq} \ensuremath{\lesssim} \ensuremath{\gtrsim}
\ensuremath{\nlesssim} \ensuremath{\ngtrsim} \ensuremath{\lessgtr} \ensuremath{\gtrless}
\ensuremath{\ngtrless} \ensuremath{\nlessgtr} \ensuremath{\prec} \ensuremath{\succ}
\ensuremath{\preccurlyeq} \ensuremath{\succcurlyeq} \ensuremath{\precsim} \ensuremath{\succsim}

\ensuremath{\nprec} \ensuremath{\nsucc} \ensuremath{\subset} \ensuremath{\supset}
\ensuremath{\nsubset} \ensuremath{\nsupset} \ensuremath{\subseteq} \ensuremath{\supseteq}
\ensuremath{\nsubseteq} \ensuremath{\nsupseteq} \ensuremath{\subsetneq} \ensuremath{\supsetneq}
_ _ \ensuremath{\uplus} \ensuremath{\sqsubset}

\ensuremath{\sqsupset} \ensuremath{\sqsubseteq} \ensuremath{\sqsupseteq} \ensuremath{\sqcap}
\ensuremath{\sqcup} \ensuremath{\oplus} \ensuremath{\ominus} \ensuremath{\otimes}
\ensuremath{\oslash} \ensuremath{\odot} \ensuremath{\circledcirc} \ensuremath{\circledast}
_ \ensuremath{\circleddash} \ensuremath{\boxplus} \ensuremath{\boxminus}

\ensuremath{\boxtimes} \ensuremath{\boxdot} \ensuremath{\vdash} \ensuremath{\dashv}
\ensuremath{\top} \ensuremath{\bot} _ _
\ensuremath{\vDash} \ensuremath{\Vdash} \ensuremath{\Vvdash} \ensuremath{\VDash}
\ensuremath{\nvdash} \ensuremath{\nvDash} \ensuremath{\nVdash} \ensuremath{\nVDash}

_ _ \ensuremath{\vartriangleleft} \ensuremath{\vartriangleright}
\ensuremath{\trianglelefteq} \ensuremath{\trianglerighteq} \ensuremath{\multimapdotbothA} \ensuremath{\multimapdotbothB}
\ensuremath{\multimap} _ \ensuremath{\intercal} \ensuremath{\veebar}
\ensuremath{\barwedge} \ensuremath{\overline{\vee}} _ _

\ensuremath{\bigwedge} \ensuremath{\bigvee} \ensuremath{\bigcap} \ensuremath{\bigcup}
\ensuremath{\diamond} \ensuremath{\cdot} \ensuremath{\star} \ensuremath{\divideontimes}
\ensuremath{\bowtie} \ensuremath{\ltimes} \ensuremath{\rtimes} \ensuremath{\leftthreetimes}
\ensuremath{\rightthreetimes} \ensuremath{\backsimeq} \ensuremath{\curlyvee} \ensuremath{\curlywedge}

\ensuremath{\Subset} \ensuremath{\Supset} \ensuremath{\Cap} \ensuremath{\Cup}
\ensuremath{\pitchfork} _ \ensuremath{\lessdot} \ensuremath{\gtrdot} 
\ensuremath{\lll} \ensuremath{\ggg} \ensuremath{\lesseqgtr} \ensuremath{\gtreqless}
_ _ \ensuremath{\curlyeqprec} \ensuremath{\curlyeqsucc}

\ensuremath{\not\curlyeqprec} \ensuremath{\not\curlyeqsucc} \ensuremath{\not\sqsubseteq} \ensuremath{\not\sqsupseteq}
_ _ \ensuremath{\lnsim} \ensuremath{\gnsim}
\ensuremath{\precnsim} \ensuremath{\succnsim} \ensuremath{\ntriangleleft} \ensuremath{\ntriangleright}
\ensuremath{\ntrianglelefteq} \ensuremath{\ntrianglerighteq} \ensuremath{\vdots} \ensuremath{\cdots}

\ensuremath{\iddots} \ensuremath{\ddots} _ _
_ \ensuremath{\dot{\in}} \ensuremath{\overline{\in}} _
\ensuremath{\underline{\in}} _ _ _
_ \ensuremath{\overline{\ni}} _ _
));

# Misc Technical
    set_codes(0x2300, qw(
\ensuremath{\diameter} _ _ _
_ \ensuremath{\barwedge} \ensuremath{\doublebarwedge} _
\ensuremath{\lceil} \ensuremath{\rceil} \ensuremath{\lfloor} \ensuremath{\rfloor}
_ _ _ _

\ensuremath{\invneg} \ensuremath{\wasylozenge} _ _
_ \ensuremath{\recorder} _ _
_ _ _ _
\ensuremath{\ulcorner} \ensuremath{\urcorner} \ensuremath{\llcorner} \ensuremath{\lrcorner}

_ _ \ensuremath{\frown} \ensuremath{\smile}
_ _ _ _
_ \ensuremath{\langle} \ensuremath{\rangle} _
_ _ _ _
));

# \usepackage{metre}
    set_codes(0x23d0, qw(
_
\metra{\b}
\metra{\mb}
\metra{\bm}
\metra{\mbb}
\metra{\bbm}
\metra{\bb}
\metra{\tsbm}
\metra{\tsmm}
\metra{\ps}));

# 2500 Box drawing (and shapes)
# 2600 Misc shapes

# 27c0 Misc math

    set_codes(0x27e4, qw(
_ _ \textlbrackdbl \textrbrackdbl
\ensuremath{\langle} \ensuremath{\rangle} _ _));

# 27f0 Suplemental arrows
    set_codes(0x27f0, qw(
_ _ _ _
_ \ensuremath{\longleftarrow} \ensuremath{\longrightarrow} \ensuremath{\longleftrightarrow}
\ensuremath{\Longleftarrow} \ensuremath{\Longrightarrow} \ensuremath{\Longleftrightarrow} \ensuremath{\longmapsfrom}
\ensuremath{\longmapsto} \ensuremath{\Longmapsfrom} \ensuremath{\Longmapsto} _));


# 2900 Suplemental arrows
    set_codes(0x2904, qw(_ \ensuremath{\Mapsfrom} \ensuremath{\Mapsto} _));

    set_codes(0x2930, qw(_ _ _ \ensuremath{\leadsto}));
    set_codes(0x2940, qw(\ensuremath{\circlearrowleft} \ensuremath{\circlearrowright} _ _));

    set_codes(0x297c, qw(\ensuremath{\strictfi} \ensuremath{\strictif} _ _));

    set_codes(0x2984, qw(_ \ensuremath{\Lparen} \ensuremath{\Rparen} _));

    set_codes(0x29b0, qw(_ \ensuremath{\bar{\varnothing}} _ \ensuremath{\vec{\varnothing}}));
    set_codes(0x29b4, qw(_ _ \ensuremath{\obar} _));
    set_codes(0x29b8, qw(\ensuremath{\obslash} _ _ _));

    set_codes(0x29c0, qw(\ensuremath{\olessthan} \ensuremath{\ogreaterthan} _ _));
    set_codes(0x29c4, qw(\ensuremath{\boxslash} \ensuremath{\boxbslash} \ensuremath{\boxast} \ensuremath{\boxcircle}));
    set_codes(0x29c8, qw(\ensuremath{\boxbox} _ _ _));

    set_codes(0x29dc, qw(_ _ _ \ensuremath{\multimapboth}));

    set_codes(0x29e0, qw(_ _ \ensuremath{\shuffle} _));
    set_codes(0x29e8, qw(_ _ _ \ensuremath{\blacklozenge}));

    set_codes(0x29f4, qw(_ \ensuremath{\setminus} \ensuremath{\bar{/}} _));
    set_codes(0x29f8, qw(\ensuremath{\big{/}} _ _ _));


# Suplemental math operators
    set_codes(0x2a00, qw(
\ensuremath{\bigodot} \ensuremath{\bigoplus} \ensuremath{\bigotimes} _
\ensuremath{\biguplus} \ensuremath{\bigsqcap} \ensuremath{\bigsqcup} _
_ \ensuremath{\varprod} _ _
\ensuremath{\iiiint} _ _ \ensuremath{\fint}

_ _ _ _
_ _ \ensuremath{\sqint} _
_ _ _ \ensuremath{\overline{\int}}
\ensuremath{\underline{\int}} \ensuremath{\Join} \ensuremath{\lhd} \ensuremath{\fatsemi}

_ _ _ \ensuremath{\hat{+}}
\ensuremath{\tilde{+}} _ _ \ensuremath{+_2}
_ _ _ _
_ _ _ _

\ensuremath{\dot{\times}} \ensuremath{\underline{\times}} _ _
_ _ _ _
_ _ _ _
_ _ _ \ensuremath{\amalg}

_ _ \ensuremath{\bar{\cup}} \ensuremath{\bar{\cap}}
_ _ _ _
_ _ _ _
_ _ _ _

_ \ensuremath{\dot{\wedge}} \ensuremath{\dot{\vee}} _
_ _ _ _
_ _ _ _
_ _ \ensuremath{\doublebarwedge} \ensuremath{\underline{\wedge}}

_ _ _ _
_ _ _ _
_ _ _ _
_ \ensuremath{\dot{\cong}} _ \ensuremath{\hat{\approx}}

_ _ _ _
\ensuremath{\Coloneqq} _ _ _
_ _ _ _
_ \ensuremath{\leqslant} \ensuremath{\geqslant} _

_ _ _ _
_ \ensuremath{\lessapprox} \ensuremath{\gtrapprox} \ensuremath{\lneq}
\ensuremath{\gneq} \ensuremath{\lnapprox} \ensuremath{\gnapprox} \ensuremath{\lesseqqgtr}
\ensuremath{\gtreqqless} _ _ _

_ _ _ _
_ \ensuremath{\eqslantless} \ensuremath{\eqslantgtr} _
_ _ _ _
_ _ _ _

_ _ _ \ensuremath{\underline{\ll}}
_ _ \ensuremath{\leftslice} \ensuremath{\rightslice}
_ _ _ _
_ _ _ \ensuremath{\preceq}


\ensuremath{\succeq} _ _ \ensuremath{\preceqq}
\ensuremath{\succeqq} \ensuremath{\precneqq} \ensuremath{\succneqq} \ensuremath{\precapprox}
\ensuremath{\succapprox} \ensuremath{\precnapprox} \ensuremath{\succnapprox} _
_ _ _ _

_ _ _ \ensuremath{\dot{\subseteq}}
\ensuremath{\dot{\supseteq}} \ensuremath{\subseteqq} \ensuremath{\supseteqq} _
_ _ _ \ensuremath{\subsetneqq}
\ensuremath{\supsetneqq} _ _ _

_ _ _ _
_ _ _ _
_ _ _ _
_ _ _ _

_ _ _ _
_ _ _ _
_ _ _ \ensuremath{\Perp}
_ _ _ _

_ _ _ _
\ensuremath{\interleave} _ _ _
_ _ _ _
\ensuremath{\biginterleave} \ensuremath{\sslash} \ensuremath{\talloblong} _
));

   set_codes(0x2e18, qw(\textinterrobangdown));
   set_codes(0x2e1a, qw(\"{-}));
   set_codes(0x2e1e, qw(\ensuremath{\dot{\sim}}));

   set_codes(0xfb00, qw(ff fi fl ffi ffl));

}
