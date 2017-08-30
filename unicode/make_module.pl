#!/usr/bin/perl

# This module creates module that maps unicode characters to their
# equivalent LaTeX escapes.  In the first phase of this program, the
# character mapping is calculated.  In the second phase of this
# program, the module containing the character mapping is printed to
# stdout.

use warnings;
use strict;
$|++;

use IO::File;

use Encode;
#use TeXEncode;
#use TeX::Encode;
#use XML::Parser;
use List::MoreUtils qw(uniq);

my %codes;
my %ccc;

my %decomp1;
my %decomp2;

parseUnicodeData();

ascii(); # 0000-007f
latin1(); # 0080-00ff
latin_extended(); # 0100-02ff
accents(); # 0300-036f, 20d0-20ff
greek(); # 0370-03ff
ding(); # 2400-27bf
other(); # 2000-2e7f, fb00-fb4f
math_alpha(); # 1d400-1d4ff

# Decomp
for (0x0000 .. 0xffff) {
    next if in_range($_, 0x0400, 0x04ff);
    next if in_range($_, 0x0600, 0x06ff);
    next if in_range($_, 0x0900, 0x10ff);
    next if in_range($_, 0x1b00, 0x1b7f);
    next if in_range($_, 0x2a80, 0x2aff);
    next if in_range($_, 0x3040, 0x30ff);
    next if in_range($_, 0xd800, 0xdfff);
    next if in_range($_, 0xfb1d, 0xfb4f);
    next if in_range($_, 0xf900, 0xfad9);
    next if $_ == 0x01ee;
    next if $_ == 0x01ef;
    next if $_ == 0x0343;
    next if $_ == 0x0374;
    next if $_ == 0x03d3;
    next if $_ == 0x1e9b;
    my $x = decomp($_);
    if ($x ne chr($_) and $x ne 'TODO') {
        $codes{$_} = $x;
    }
}

$codes{$_} =~ s[^(\\\W)\{(\w)\}$][$1$2]g for keys %codes; # translate "\'{x}" to "\'x"

sub in_range {
    my ($val, $low, $hi) = @_;
    return ($low <= $val && $val <= $hi);
}

sub parseUnicodeData {
    my $fh = IO::File->new("UnicodeData.txt", 'r');
    while (<$fh>) {
        my @fields = split ';', $_;
        my $code = hex($fields[0]);
        my ($decomp1, $dummy, $decomp2) = $fields[5] =~ m/^([0-9A-F]+)( ([0-9A-F]+))?/;
        $ccc{$code} = $fields[3];
        $decomp1{$code} = hex($decomp1) if defined $decomp1;
        $decomp2{$code} = hex($decomp2) if defined $decomp2;
    }
}

sub set_codes {
    my ($char, @codes) = @_;
    for (@codes) {
        if ($_ eq '_') { delete $codes{$char} }
        else { $codes{$char} = $_ }
        $char++;
    }
}

########################################
# Output

########################
# DEBUGGING CODE
#for my $num (0x00a0 .. 0x03ff) {
#    printf("%04x %s\n", $num, encode_utf8(chr($num))) if not exists $codes{$num};
#}

#for my $num (sort {$a <=> $b} keys %codes) {
#    printf("%04x %s %s\n", $num, encode_utf8(chr($num)), $codes{$num}) if exists $ccc{$num} and $ccc{$num} != 0;
#    
#}
# END DEBUGGING CODE
########################

print <<'EOT';
package TeX::Unicode;
use warnings;
use strict;

use Carp;
use Exporter qw(import);

our @EXPORT = qw(unicode2tex);
our @EXPORT_OK = qw(%CODES %CCC);

our %CODES;
our %CCC;

#sub unicode2tex_old {
#    my ($str) =  @_;
#    $str =~ s[([^\x00-\x80])][\{@{[$CODES{$1} or
#         warn "Unknown Unicode charater: $1 ", sprintf("0x%x", ord($1)) and
#         $1]}\}]g;
#    return $str;
#}

sub unicode2tex {
    my ($str) = @_;
    my @out;
    for (unpack("U*", $str)) {
        if (exists $CODES{$_}) {
            if (exists $CCC{$_}) {
                my $old = pop @out;
                ($old = '{}',
                 carp sprintf 'Combining character at start of string:  %s (U+%04x)', chr($_), $_)
                    if not defined $old;
                my $new = $CODES{$_};
                $new =~ s[\{\}][$old];
                $new =~ s[\{([ij])\}][\{\\$1\}]g
                    if ($CCC{$_} == 230 || $CCC{$_} == 234);
                push @out, "{$new}";
            } else {
                push @out, "{$CODES{$_}}";
            }
        } else {
            carp sprintf "Unknown Unicode character: %s (U+x%04x)", chr($_), $_
                if $_ >= 0x80;
            push @out, chr($_);
        }
    }

    return join('', @out);
}

%CCC = (
EOT
    for (sort {$a <=> $b} keys %ccc) {
        printf("    0x%04x => %d,\n", $_, $ccc{$_}) if exists $codes{$_} and $ccc{$_} != 0;
    }
    print <<'EOT';
    );

%CODES = (
EOT
    for (sort {$a <=> $b} keys %codes) {
        my $x = $codes{$_};
        $x =~ s[\\][\\\\]g;
        $x =~ s['][\\']g;
        printf("    0x%04x => '%s',\n", $_, $x);
    }
    print <<'EOT';
    );
1;
EOT

# END Output
########################################

########################################
# The following code to calculates the mapping.

sub decomp {
    my ($char) = @_;

    if (exists $codes{$char}) {
        return $codes{$char};
    } elsif ($char == 0x1fc0 or $char == 0x1fc1 or
        $char == 0x1fbd or $char == 0x1fbe or $char == 0x1fbf or
        $char == 0x1fcd or $char == 0x1fce or $char == 0x1fcf or
        $char == 0x1fdd or $char == 0x1fde or $char == 0x1fdf or
        $char == 0x1fed or $char == 0x1fee or $char == 0x1fef or
        $char == 0x1ffd or $char == 0x1ffe) {
        return "TODO";
    } elsif (exists $decomp2{$char}) {
        my $x = decomp($decomp1{$char});
        if ($x =~ m[^\\textgreek{(.*)}$]) {
            if ($decomp2{$char} == 0x0300) {
                return "\\textgreek{`$1}";
            } elsif ($decomp2{$char} == 0x0301) {
                return "\\textgreek{'$1}";
            } elsif ($decomp2{$char} == 0x0304) {
                return "\\textgreek{\\={$1}}";
            } elsif ($decomp2{$char} == 0x0306) {
                return "\\textgreek{\\u{$1}}";
            } elsif ($decomp2{$char} == 0x0308) {
                return "\\textgreek{\"$1}";
            } elsif ($decomp2{$char} == 0x0313) {
                return "\\textgreek{>$1}";
            } elsif ($decomp2{$char} == 0x0314) {
                return "\\textgreek{<$1}";
            } elsif ($decomp2{$char} == 0x0342) {
                return "\\textgreek{\\~{$1}}";
            } elsif ($decomp2{$char} == 0x0345) {
                return "\\textgreek{$1|}";
            } else {
                printf "ERROR: %04x %04x %04x %s\n", $char, $decomp1{$char}, $decomp2{$char}, $x;
                exit 1;
            }
        } else {
            die unless exists $codes{$decomp2{$char}};
            die if $codes{$decomp2{$char}} =~ /\{\}.*\{\}/;
            die unless $codes{$decomp2{$char}} =~ /\{\}/;
            my $accent = $codes{$decomp2{$char}};
            my $body = decomp($decomp1{$char});
            $accent =~ s/\{\}/\{$body\}/;
            $accent =~ s/\{([ij])\}/\{\\$1\}/g
                if ($ccc{$decomp2{$char}} == 230 || # Combining class above
                    $ccc{$decomp2{$char}} == 234); # Combining class double above
            return $accent;
        }
    } elsif (exists $decomp1{$char}) { return decomp($decomp1{$char});
    } else { return chr($char); }    
}

sub ascii {
# Taken from Table 328 of "The Comprehensive LaTeX Symbol List"
    set_codes(0x22, qw(\textquotedbl \# \$ \% \&));
    set_codes(0x3c, qw(\textless _ \textgreater));
    set_codes(0x5c, qw(\textbackslash));
    set_codes(0x5e, qw(\^{}));
    set_codes(0x5f, qw(\_));
    set_codes(0x7b, qw(\{));
    set_codes(0x7c, qw(\textbar));
    set_codes(0x7d, qw(\}));
    set_codes(0x7e, qw(\~{})); 
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

    # We skip things from Table 329 that are definable by
    # decomposition but the following remain
    set_codes(0x00c5, '\AA');
    set_codes(0x00c6, '\AE');
    set_codes(0x00d0, '\DH');
    set_codes(0x00d7, '\texttimes');
    set_codes(0x00d8, '\O');
    set_codes(0x00de, '\TH');
    set_codes(0x00df, '\ss');
    set_codes(0x00e5, '\aa');
    set_codes(0x00e6, '\ae');
    set_codes(0x00f0, '\dh');
    set_codes(0x00f7, '\textdiv');
    set_codes(0x00f8, '\o');
    set_codes(0x00fe, '\th');
}

sub latin_extended {
    # Latin A
    set_codes(0x0110, qw(\DJ));
    set_codes(0x0111, qw(\dj));
    set_codes(0x0126, qw(\B{H}));
    set_codes(0x0127, qw(\b{h}));
    set_codes(0x0131, qw(\i));
    set_codes(0x0132, qw(\IJ));
    set_codes(0x0133, qw(\ij));
    set_codes(0x0141, qw(\L));
    set_codes(0x0142, qw(\l));
    set_codes(0x0149, qw('n));
    set_codes(0x014a, qw(\NG));
    set_codes(0x014b, qw(\ng));
    set_codes(0x0152, qw(\OE));
    set_codes(0x0153, qw(\oe));
    set_codes(0x0166, qw(\B{T}));
    set_codes(0x0167, qw(\B{t}));
    # Latin B
    set_codes(0x0192, qw(\textflorin)); # TODO
    set_codes(0x0195, qw(\texthvlig)); # TODO
    set_codes(0x019e, qw(\textnrleg)); # TODO
    set_codes(0x01a0, qw(\OHORN));
    set_codes(0x01a1, qw(\ohorn));
    set_codes(0x01af, qw(\UHORN));
    set_codes(0x01b0, qw(\uhorn));
    set_codes(0x01c2, qw(\textdoublepipe)); # Missing (TODO: double check)
    set_codes(0x0237, qw(\j));
    # Spacing modifier letters
    set_codes(0x02bc, qw('));
    set_codes(0x02c6, qw(\^{} \v{} \|{} \={} \'{} \`{} \textsyllabic{} \b{}));
    set_codes(0x02d8, qw(\u{} \.{} \r{} \k{} \~{} \H{}));
}

sub accents {
    my @accents = qw(
    `  '  ^  ~  =  __ u  .
    "  h  r  H  v  |  U  G
    
    __ textroundcap __ __ __ __ __ __
    __ __ __ __ __ __ __ __
    
    __ __           __ d  textsubumlaut textsubring   cb           c 
    k  textsyllabic __ __ __            textsubcircum textsubbreve __
    
    textsubtilde b  __ __ __ __ __ __
    __ __ __ __ __ __ __ __
    
    __ __ __ __ __ __ __ __
    __ __ __ __ __ __ __ __
    
    __ __ __ __ __ __ __ __
    __ __ __ __ __ __ __ __
    
    __ __ __ __ __ __ __ __
    __ __ __ __ __ __ __ __
    );


# TODO: these are the "problem" accents
#\`{i}  \'{i}  \^{i}  \~{i}  \={i}  \u{i}  \.{i}
#
#\"{i}  \h{i}  \r{i}  \H{i}  \v{i}  \|{i}  \U{i}  \G{i}    
#
#\textroundcap{i}
#
#%\d{i}  \textsubumlaut{i} \textsubring{i}   \cb{i}           \c{i} 
#
#%\k{i}  \textsyllabic{i}               \textsubcircum{i} \textsubbreve{i}     
#
#%\textsubtilde{i} \b{i}       
#
#    0x1e2f \'{\"{i}}
#
#
#\`{j}  \'{j}  \^{j}  \~{j}  \={j}  \u{j}  \.{j}
#
#\"{j}  \h{j}  \r{j}  \H{j}  \v{j}  \|{j}  \U{j}  \G{j}    
#
#\textroundcap{j}
#
#    0x01f0 \v{j}

    
    # Accents
    for (0x0300 .. 0x036f) {
        set_codes($_, ($accents[$_-0x300] ne '__' ?
                       "\\$accents[$_-0x300]\{\}" : '_'));
    }
    set_codes(0x0305, qw(\ensuremath{\overline{}}));
    set_codes(0x20d7, qw(\ensuremath{\vec{}}));
    set_codes(0x20db, qw(\ensuremath{\dddot{}} \ensuremath{\ddddot{}}));
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

sub ding {
    # Circled 1..9, A-Z, a-z
    set_codes($_, "\\ding{" . (172 - 0x2460 + $_) . "}") for (0x2460 .. 0x2469);
    set_codes($_, "\\textcircled{" . chr(ord('A') - 0x24b6 + $_) . "}") for (0x24b6 .. 0x24cf);
    set_codes($_, "\\textcircled{" . chr(ord('a') - 0x24d0 + $_) . "}") for (0x24d0 .. 0x24e9);

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

# These may override the \ding{} and \textcircled{} codes
    set_codes(0x2422, qw(\textblank));
    set_codes(0x2423, qw(\textvisiblespace));
    set_codes(0x24ea, "\\textcircled{0}");
    set_codes(0x24c5, "\\textcircledP");
    set_codes(0x24c7, "\\circledR");

# TODO: 2500 .. 259f pmboxdraw
# 2571 \diagup
# TODO: 25a0 .. box drawing

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

sub math_alpha {
    my $char = 0x1d400;
    my @latin = map {chr($_)} (0x41 .. 0x5a, 0x61 .. 0x7a);
    my @greek = qw(A B \Gamma \Delta E Z H \Theta I K \Lambda M N \Xi
                   O \Pi R \varTheta \Sigma T \Upsilon \Phi X \Psi \Omega \nabla
                   \alpha \beta \gamma \delta \varepsilon \zeta \eta
                   \theta \iota \kappa \lambda \mu \nu \xi o \pi \rho
                   \varsigma \sigma \tau \upsilon \varphi \chi \psi \omega
                   \partial \epsilon \vartheta \varkappa \phi \varrho \varpi);
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
_ \textinterrobang _ _
));

    set_codes(0x2050, qw(
_ _ _ _
_ _ _ \ensuremath{^{\prime\prime\prime\prime}}
_ _ _ _
_ _ _ \ensuremath{\mkern4mu}

\nolinebreak _ _ _));

# Super and subscripts
set_codes(0x2070,
          (map { "\\textsuperscript{$_}" } qw[0 i]),
          qw[_ _],
          (map { "\\textsuperscript{$_}" } qw[4 5 6 7 8 9 + - = ( ) n]),
          (map { "\\textsubscript{$_}" } qw[0 1 2 3 4 5 6 7 8 9 + - = ( )]),
          qw[_],
          (map { "\\textsubscript{$_}" } qw[a e o x \textschwa h k l m n p s t]));

# Currency Symbols
    set_codes(0x20a0, qw(
_ \textcolonmonetary _ _
  \textlira _ \textnaira _
_ \textwon  _ \textdong
\texteuro _ _ _

_ \textpeso \textguarani _
));

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

\ensuremath{\mathscr{E}} \ensuremath{\mathscr{F}} \ensuremath{\Finv} \ensuremath{\mathscr{M}}
\ensuremath{\mathscr{o}} \ensuremath{\aleph} \ensuremath{\beth} \ensuremath{\gimel}
\ensuremath{\daleth} _ _ \fax
\ensuremath{\mathbb{\pi}} \ensuremath{\mathbb{\gamma}} \ensuremath{\mathbb{\Gamma}} \ensuremath{\mathbb{\Pi}}

\ensuremath{\mathbb{\sum}} \ensuremath{\Game} _ _
\ensuremath{\Yup} \ensuremath{\mathbb{D}} \ensuremath{\mathbb{d}} \ensuremath{\mathbb{e}}
\ensuremath{\mathbb{i}} \ensuremath{\mathbb{j}} _ \ensuremath{\bindnasrepma}
_ _ _ _
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

\ensuremath{\dashleftarrow} _ \ensuremath{\dashrightarrow} _
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
\ensuremath{\nlessgtr} \ensuremath{\ngtrless} \ensuremath{\prec} \ensuremath{\succ}
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

    set_codes(0x23b0, qw(\ensuremath{\left\lmoustache\right.} \ensuremath{\left\rmoustache\right.}));

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
    set_codes(0x2904, qw(_ _ \ensuremath{\Mapsfrom} \ensuremath{\Mapsto}));

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
