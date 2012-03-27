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

########################################
# Taken from TeX::Encode 1.3
$codes{0x0126} = '\=H';
$codes{0x0127} = '\=h';
$codes{0x013f} = '\.L';
$codes{0x0140} = '\.l';
$codes{0x0166} = '\=T';
$codes{0x0167} = '\=t';
$codes{0x01cd} = '\vA';
$codes{0x01ce} = '\va';
$codes{0x01cf} = '\vI';
$codes{0x01d0} = '\vi';
$codes{0x01d1} = '\vO';
$codes{0x01d2} = '\vo';
$codes{0x01d3} = '\vU';
$codes{0x01d4} = '\vu';
$codes{0x01e2} = '\={\AE}';
$codes{0x01e3} = '\={\ae}';
$codes{0x01e6} = '\vG';
$codes{0x01e7} = '\vg';
$codes{0x01e8} = '\vK';
$codes{0x01e9} = '\vk';
$codes{0x01ea} = '\kO';
$codes{0x01eb} = '\ko';
$codes{0x01f0} = '\vj';
$codes{0x01f4} = '\'G';
$codes{0x01f8} = '\`N';
$codes{0x01f9} = '\`n';
$codes{0x01fa} = '\'{\AA}';
$codes{0x01fb} = '\'{\aa}';
$codes{0x01fc} = '\'{\AE}';
$codes{0x01fd} = '\'{\ae}';
$codes{0x01fe} = '\'{\O}';
$codes{0x01ff} = '\'{\o}';
$codes{0x0200} = '\CA';
$codes{0x0201} = '\Ca';
$codes{0x0202} = '\fA';
$codes{0x0203} = '\fa';
$codes{0x0204} = '\CE';
$codes{0x0205} = '\Ce';
$codes{0x0206} = '\fE';
$codes{0x0207} = '\fe';
$codes{0x0208} = '\CI';
$codes{0x0209} = '\Ci';
$codes{0x020a} = '\fI';
$codes{0x020b} = '\fi';
$codes{0x020c} = '\CO';
$codes{0x020d} = '\Co';
$codes{0x020e} = '\fO';
$codes{0x020f} = '\fo';
$codes{0x0210} = '\CR';
$codes{0x0211} = '\Cr';
$codes{0x0212} = '\fR';
$codes{0x0213} = '\fr';
$codes{0x0214} = '\CU';
$codes{0x0215} = '\Cu';
$codes{0x0216} = '\fU';
$codes{0x0217} = '\fu';
$codes{0x021e} = '\vH';
$codes{0x021f} = '\vh';
$codes{0x0226} = '\.A';
$codes{0x0227} = '\.a';
$codes{0x0228} = '\cE';
$codes{0x0229} = '\ce';
$codes{0x022e} = '\.O';
$codes{0x022f} = '\.o';
$codes{0x0232} = '\=Y';
$codes{0x0233} = '\=y';
$codes{0x1e00} = '\DA';
$codes{0x1e01} = '\Da';
$codes{0x1e02} = '\.B';
$codes{0x1e03} = '\.b';
$codes{0x1e04} = '\dB';
$codes{0x1e05} = '\db';
$codes{0x1e06} = '\bB';
$codes{0x1e07} = '\bb';
$codes{0x1e0a} = '\.D';
$codes{0x1e0b} = '\.d';
$codes{0x1e0c} = '\dD';
$codes{0x1e0d} = '\dd';
$codes{0x1e0e} = '\bD';
$codes{0x1e0f} = '\bd';
$codes{0x1e10} = '\cD';
$codes{0x1e11} = '\cd';
$codes{0x1e12} = '\VD';
$codes{0x1e13} = '\Vd';
$codes{0x1e18} = '\VE';
$codes{0x1e19} = '\Ve';
$codes{0x1e1a} = '\TE';
$codes{0x1e1b} = '\Te';
$codes{0x1e1e} = '\.F';
$codes{0x1e1f} = '\.f';
$codes{0x1e20} = '\=G';
$codes{0x1e21} = '\=g';
$codes{0x1e22} = '\.H';
$codes{0x1e23} = '\.h';
$codes{0x1e24} = '\dH';
$codes{0x1e25} = '\dh';
$codes{0x1e26} = '\"H';
$codes{0x1e27} = '\"h';
$codes{0x1e28} = '\cH';
$codes{0x1e29} = '\ch';
$codes{0x1e2c} = '\TI';
$codes{0x1e2d} = '\Ti';
$codes{0x1e30} = '\'K';
$codes{0x1e31} = '\'k';
$codes{0x1e32} = '\dK';
$codes{0x1e33} = '\dk';
$codes{0x1e34} = '\bK';
$codes{0x1e35} = '\bk';
$codes{0x1e36} = '\dL';
$codes{0x1e37} = '\dl';
$codes{0x1e3a} = '\bL';
$codes{0x1e3b} = '\bl';
$codes{0x1e3c} = '\VL';
$codes{0x1e3d} = '\Vl';
$codes{0x1e3e} = '\'M';
$codes{0x1e3f} = '\'m';
$codes{0x1e40} = '\.M';
$codes{0x1e41} = '\.m';
$codes{0x1e42} = '\dM';
$codes{0x1e43} = '\dm';
$codes{0x1e44} = '\.N';
$codes{0x1e45} = '\.n';
$codes{0x1e46} = '\dN';
$codes{0x1e47} = '\dn';
$codes{0x1e48} = '\bN';
$codes{0x1e49} = '\bn';
$codes{0x1e4a} = '\VN';
$codes{0x1e4b} = '\Vn';
$codes{0x1e54} = '\'P';
$codes{0x1e55} = '\'p';
$codes{0x1e56} = '\.P';
$codes{0x1e57} = '\.p';
$codes{0x1e58} = '\.R';
$codes{0x1e59} = '\.r';
$codes{0x1e5a} = '\dR';
$codes{0x1e5b} = '\dr';
$codes{0x1e5e} = '\bR';
$codes{0x1e5f} = '\br';
$codes{0x1e60} = '\.S';
$codes{0x1e61} = '\.s';
$codes{0x1e62} = '\dS';
$codes{0x1e63} = '\ds';
$codes{0x1e6a} = '\.T';
$codes{0x1e6b} = '\.t';
$codes{0x1e6c} = '\dT';
$codes{0x1e6d} = '\dt';
$codes{0x1e6e} = '\bT';
$codes{0x1e6f} = '\bt';
$codes{0x1e70} = '\VT';
$codes{0x1e71} = '\Vt';
$codes{0x1e74} = '\TU';
$codes{0x1e75} = '\Tu';
$codes{0x1e76} = '\VU';
$codes{0x1e77} = '\Vu';
$codes{0x1e7c} = '\~V';
$codes{0x1e7d} = '\~v';
$codes{0x1e7e} = '\dV';
$codes{0x1e7f} = '\dv';
$codes{0x1e80} = '\`W';
$codes{0x1e81} = '\`w';
$codes{0x1e82} = '\'W';
$codes{0x1e83} = '\'w';
$codes{0x1e84} = '\"W';
$codes{0x1e85} = '\"w';
$codes{0x1e86} = '\.W';
$codes{0x1e87} = '\.w';
$codes{0x1e88} = '\dW';
$codes{0x1e89} = '\dw';
$codes{0x1e8a} = '\.X';
$codes{0x1e8b} = '\.x';
$codes{0x1e8c} = '\"X';
$codes{0x1e8d} = '\"x';
$codes{0x1e8e} = '\.Y';
$codes{0x1e8f} = '\.y';
$codes{0x1e90} = '\^Z';
$codes{0x1e91} = '\^z';
$codes{0x1e92} = '\dZ';
$codes{0x1e93} = '\dz';
$codes{0x1e94} = '\bZ';
$codes{0x1e95} = '\bz';
$codes{0x1e96} = '\bh';
$codes{0x1e97} = '\"t';
$codes{0x1e98} = '\rw';
$codes{0x1e99} = '\ry';
$codes{0x1ea0} = '\dA';
$codes{0x1ea1} = '\da';
$codes{0x1ea2} = '\hA';
$codes{0x1ea3} = '\ha';
$codes{0x1eb8} = '\dE';
$codes{0x1eb9} = '\de';
$codes{0x1eba} = '\hE';
$codes{0x1ebb} = '\he';
$codes{0x1ebc} = '\~E';
$codes{0x1ebd} = '\~e';
$codes{0x1ec8} = '\hI';
$codes{0x1ec9} = '\hi';
$codes{0x1eca} = '\dI';
$codes{0x1ecb} = '\di';
$codes{0x1ecc} = '\dO';
$codes{0x1ecd} = '\do';
$codes{0x1ece} = '\hO';
$codes{0x1ecf} = '\ho';
$codes{0x1ee4} = '\dU';
$codes{0x1ee5} = '\du';
$codes{0x1ee6} = '\hU';
$codes{0x1ee7} = '\hu';
$codes{0x1ef2} = '\`Y';
$codes{0x1ef3} = '\`y';
$codes{0x1ef4} = '\dY';
$codes{0x1ef5} = '\dy';
$codes{0x1ef6} = '\hY';
$codes{0x1ef7} = '\hy';
$codes{0x1ef8} = '\~Y';
$codes{0x1ef9} = '\~y';
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
    start($ipa, qw({amssymb} {textcomp} [tone]{tipa} {tipx}));
    start($greek, qw({amssymb})); # amssymb is for \backepsilon and \varkappa
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

# TODO: 0x2254 (:= not :-)        

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
        if (defined $other1 and not defined $self) {
        #unless (defined $self and defined $other1 and $other1 eq $self) {
            printf("%04x %s", $number, encode_utf8(chr($number)));
            # XML is better than XML.old
            # XML is better than LATEX_Escapes when they conflict
            # XML is a superset of LATEX_Escapes
            #print(" ($other2)") if defined $other2;
            # XML is better than CHAR_MAP when they conflict
            # There are some in CHARP_MAP that are missing from XML
            print(" ($other1)") if defined $other1;
            #print(" [$self]") if defined $self;
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
    s[\{\{([^{}]*)\}\}][{$1}]g; # Remove doubled up {{x}} (but dont do {{x}y{z}})

    $latex = $_ if $tag eq '<latex>';
    $ams = $_ if $tag eq '<AMS>';
}
