#!/usr/bin/perl

# This module creates the TeX files in the test/ folder, which are used to test the mapping defined by TeX::Unicode.
#
# Usage: ./make_tests.pl

use warnings;
use strict;
$|++;

use IO::File;

use Encode;
#use TeXEncode;
#use TeX::Encode;
#use XML::Parser;
use List::MoreUtils qw(uniq);
use TeX::Unicode;

sub in_range {
    my ($val, $low, $hi) = @_;
    return ($low <= $val && $val <= $hi);
}

sub start { # Prints the TeX header for the TEST_TEX phase
    my ($file, @packages) = @_;
    print $file "\\documentclass[11pt]{article}\n\\usepackage[T1]{fontenc}\n";
    print $file "\\usepackage$_\n" for @packages;
    print $file "\\begin{document}\n\n";

# Other packages that we tried using but that either didn't work, led to conflicts, or weren't needed:
#    %\usepackage{cite}
#    %\usepackage{amsfonts}
#    %%\usepackage[mathscr,mathcal]{euscript}
#    %\usepackage{txfonts}
#    %\usepackage{pxfonts}
#    %\usepackage{wasysym}
#    %\usepackage{stmaryrd}
#    \usepackage{mathdesign}
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

}

my ($latin, $main, $greek, $ding, $math_alpha) =
    map { IO::File->new("test/$_.tex", 'w') } qw(latin main greek ding math_alpha);

start($latin, qw({textcomp} {tipx}));
print $latin "\\renewcommand{\\|}{} % \\usepackage{fc}\n";
print $latin "\\newcommand{\\B}{} % \\usepackage{fc}\n";
print $latin "\\newcommand{\\G}{} % \\usepackage{fc}\n";
print $latin "\\newcommand{\\U}{} % \\usepackage{fc}\n";
print $latin "\\newcommand{\\h}{} % \\usepackage{vntex}\n";
print $latin "\\newcommand{\\OHORN}{} % \\usepackage{vntex}\n";
print $latin "\\newcommand{\\ohorn}{} % \\usepackage{vntex}\n";
print $latin "\\newcommand{\\UHORN}{} % \\usepackage{vntex}\n";
print $latin "\\newcommand{\\uhorn}{} % \\usepackage{vntex}\n";
print $latin "\\newcommand{\\textsubbreve}{} % DOES NOT EXIST\n";
print $latin "\\newcommand{\\cb}{} % \\usepackage{combelow}\n";

start($greek, qw({amssymb} [greek,english]{babel} {teubner}));
print $math_alpha "% Note: {amssymb} is for \\backepsilon and \\varkappa\n";

start($math_alpha, qw({amsmath} {amssymb} {bbold} {mathrsfs} {sansmath}));
print $math_alpha "% Note \\mathscr is defined only for upper case letters\n";
print $math_alpha "\\newcommand{\\mathbfscr}{} % Doesn't actually exist\n";
print $math_alpha "\\newcommand{\\mathbffrak}{} % Doesn't actually exist\n";
print $math_alpha "\\newcommand{\\mathsfbfsl}{} % Doesn't actually exist\n";

start($ding, qw({amssymb} {pifont} {pxfonts} {skak} {wasysym}));

start($main, qw({metre} {amsmath} {fixltx2e} {mathrsfs} {stmaryrd}
                {txfonts} {marvosym} {mathdots} {mathbbol}
                {shuffle} {tipa} {wasysym} {xfrac}));
print $main "% Note: {metre} must load before {amsmath}\n";
print $main "% {metre} is for \\metra\n";
print $main "% {fixltx2e} is for \\textsubscript\n";
print $main "% {mathrsfs} is for \\mathscr\n";
print $main "% {marvosym} is for \\Pfund and \\fax\n";
print $main "% {mathdots} is for \\iddots\n";
print $main "% {mathbbol} is for \\Lparen and \\Rparen\n";
print $main "% {shuffle} is for \\shuffle\n";
print $main "% {tipa} is for \\textschwa\n";
print $main "% {wasysym} is for \\diameter, \\invneg, \\wasylozenge, and \\recorder\n";

print "a\n";
print unicode2tex('b'), "\n";
print "c\n";

for (0x0000..0x2fff, 0xfb00..0xfb04, 0x1d400..0x1d7ff) { #sort {$a <=> $b} keys %TeX::Unicode::CODES) {
    my $file = (
        in_range($_, 0x0000, 0x036f) ? $latin :
        in_range($_, 0x0370, 0x03ff) ? $greek :
        in_range($_, 0x0400, 0x1dff) ? undef : # omitted: hebrew, arabic, etc.
        in_range($_, 0x1e00, 0x1eff) ? $latin :
        in_range($_, 0x1f00, 0x1fff) ? $greek :
        in_range($_, 0x2000, 0x23ff) ? $main :
        in_range($_, 0x2400, 0x27bf) ? $ding :
        #   2400.. 27bf ding
        #     2400 control
        #     2460 digits
        #     2500 box drawing
        #     25a0 shapes
        #     2600 misc
        #     2700 ding
        #     2733 -> 01..60 [05,0A,0B,28,4c,4e,53,54,55,57,5f,60,68-75,95,96,97,b0,bf]
        #             13 [\checkmark]
        #       
        #   301a.. 301b open brackets
        #   fb00.. fb04 *ffil
        # 2000-2bff, 2e00-2e7f # Symbols and punctuation
        # 3000-3030 # CJK punctuation
        in_range($_, 0x27c0, 0x2e7f) ? $main :
        in_range($_, 0xfb00, 0xfb04) ? $latin :
        $_ >=0x1d400 && $_ <=0x1d7ff ? $math_alpha :
        undef);

    my $tex = unicode2tex(chr($_));
    print $file sprintf("%04x X%sX\n\n", $_, $tex) if defined $file and $tex ne chr($_);
}

print $_ "\\end{document}\n" for ($latin, $main, $greek, $ding, $math_alpha);
