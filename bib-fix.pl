#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use Text::BibTeX;
use Text::BibTeX qw(:subs);
use Text::BibTeX::Value;
use TeX::Encode;
use TeX::Unicode;
use HTML::Entities;
use Encode;

use Text::BibTeX::Months;

use Getopt::Long qw(:config auto_version auto_help);


# TODO: move copyright from abstract to copyright field

############
# Options
############
#
# Omit fields (filtered by type or other fields)
# Omit if matches
# Non-encoded fields (e.g. doi and url)
# Comma at end
# Key: Keep vs generate
# Field order
#
# Author, Editor: title case, initialize, last-first
# Author, Editor, Affiliation(?): List of renames
# Booktitle, Journal, Publisher*, Series, School, Institution, Location*, Edition*, Organization*, Publisher*, Address*, Language*:
#  List of renames (regex?)
#
# Title
#  Captialization: Initialisms, After colon, list of proper names
#
# ISBN: 10 vs 13 vs native, no-dash
# ISSN: Print vs Electronic
# Keywords: ';' vs ','
#
#

$main::VERSION=1.0;

my ($DEBUG, $GENERATE_KEY, $COMMA) = (0, 1, 1);
my %NO_ENCODE_FIELD = ('doi' => 1, 'url' => 1, 'eprint' => 1);
#my %OMIT =

GetOptions(
    'debug!' => \$DEBUG,
    #no-defaults
    'generate-keys!' => \$GENERATE_KEY,
    'comma!' => \$COMMA,
    'encode=s' => sub { delete $NO_ENCODE_FIELD{$_[1]} },
    'no-encode=s' => sub { $NO_ENCODE_FIELD{$_[1]} = 1 }
    );

# TODO: omit type-regex field-regex (existing entry is in scope)

# Warn about non-four-digit year
# Omit:class/type
# Include:class/type
# no issn, no isbn
# known fields
# SIGPLAN
# title-case after ":"
# Warn if first alpha after ":" is not capitalized
# Flag about whether to Unicode, HTML, or LaTeX encode
# purify_string

=head1 SYNOPSIS

bibscrape [options] <url> ...

=head2 OPTIONS

=item --omit=field

    Omit a particular field from the output.

=item --debug

    Print debug data (TODO: make it verbose and go to STDERR)

=cut

# TODO:
#  abstract:
#  - paragraphs: no marker but often we get ".<Uperchar>" or "<p></p>"
#  - pass it through par
#  author as editors?
#  Put upper case words in {.} (e.g. IEEE)
#  detect fields that are already de-unicoded (e.g. {H}askell or $p$)
#  move copyright from abstract to copyright field
#END TODO

my $file = new Text::BibTeX::File "<-";

while (my $entry = new Text::BibTeX::Entry $file) {
    # Doi field: remove "http://hostname/" or "DOI: "
    $entry->set('doi', $entry->get('url')) if (
        not $entry->exists('doi') and
        ($entry->get('url') || "") =~ m[^http://dx.doi.org/.*$]);
    update($entry, 'doi', sub { s[http://[^/]+/][]i; s[DOI:\s*][]ig; });

    # Page numbers: no "pp." or "p."
    update($entry, 'pages', sub { s[pp?\.\s*][]ig; });

    for (['issue', 'number'], ['keyword', 'keywords']) {
        # Fix broken field names (SpringerLink and ACM violate this)
        if ($entry->exists($_->[0]) and not $entry->exists($_->[1])) {
            $entry->set($_->[1], $entry->get($_->[0]));
            $entry->delete($_->[0]);
        }
    }

    # TODO: remove empty fields

    # Ranges: convert "-" to "--"
    # TODO: might misfire if "-" doesn't represent a range, Common for tech report numbers
    for my $key ('chapter', 'month', 'number', 'pages', 'volume', 'year') {
        update($entry, $key, sub { s[\s*-+\s*][--]ig; });
        update($entry, $key, sub { s[n/a--n/a][]ig; $_ = undef if $_ eq "" });
        # TODO: single element range as x not x--x
    }

    # TODO: ISBN: 10 vs 13 vs native, dash vs no-dash vs native
    # TODO: ISSN: Print vs electronic vs native, dash vs no-dash vs native
    # TODO: Keywords: ';' vs ','

    # TODO: Title Capticalization: Initialisms, After colon, list of proper names
    # TODO: Author, Editor, Affiliation: List of renames
# Booktitle, Journal, Publisher*, Series, School, Institution, Location*, Edition*, Organization*, Publisher*, Address*, Language*:
#  List of renames (regex?)


    # Don't include pointless URLs to publisher's page
    # TODO: via Omit if matches
    update($entry, 'url', sub {
        $_ = undef if m[^(http://dx.doi.org/
                         |http://doi.acm.org/
                         |http://portal.acm.org/citation.cfm
                         |http://www.jstor.org/stable/
                         |http://www.sciencedirect.com/science/article/)]x; } );
    # TODO: via omit if empty
    update($entry, 'note', sub { $_ = undef if $_ eq "" });
    # TODO: add $doi to omit if matches
    update($entry, 'note', sub { $_ = undef if $_ eq ($entry->get('doi') or "") });

    # Collapse spaces and newlines
    for my $field (qw(
      author editor affiliation title
      howpublished booktitle journal volume number series jstor_issuetitle
      type jstor_articletype school institution location
      chapter pages articleno numpages
      edition month year issue_date jstor_formatteddate
      organization publisher address
      language isbn issn doi eid acmid url eprint bib_scrape_url
      keywords copyright)) {
        update($entry, $field, sub { $_ =~ s/\s+/ /sg; });
    }

    # Eliminate Unicode but not for doi and url fields (assuming \usepackage{url})
    # TODO: non-encoded fields
    for my $field ($entry->fieldlist()) {
        warn "Undefined $field" unless defined $entry->get($field);
        $entry->set($field, latex_encode($entry->get($field)))
            unless exists $NO_ENCODE_FIELD{$field};
    }

    # Generate an entry key
    # TODO: Formats: author/editor1.last year title/journal.abbriv
    # TODO: Key may fail on unicode names? Remove doi?
    if ($GENERATE_KEY or not defined $entry->key()) {
        my ($name) = ($entry->names('author'), $entry->names('editor'));
        #$organization, or key
        if ($name and $entry->exists('year')) {
            ($name) = purify_string(join("", $name->part('last')));
            $entry->set_key($name . ':' . $entry->get('year') .
                            ($entry->exists('doi') ? ":" . $entry->get('doi') : ""));
        }
    }

    # Use bibtex month macros
    update($entry, 'month', # Must be after field encoding
           sub { my @x = split qr[\b];
                 for (1..$#x) {
                     $x[$_] = "" if $x[$_] eq "." and str2month(lc $x[$_-1]);
                 }
                 $_ = new Text::BibTeX::Value(
                     map { (str2month(lc $_)) or ([Text::BibTeX::BTAST_STRING, $_]) }
                     map { $_ ne "" ? $_ : () } @x)});

    # Put fields in a standard order.
    # TODO: option
    my @field_order = qw(
      author editor affiliation title
      howpublished booktitle journal volume number series jstor_issuetitle
      type jstor_articletype school institution location
      chapter pages articleno numpages
      edition month year issue_date jstor_formatteddate
      organization publisher address
      language isbn issn doi eid acmid url eprint bib_scrape_url
      note annote keywords abstract copyright);
    for my $field ($entry->fieldlist()) {
        die "Unknown field: $field.\n" unless grep { $field eq $_ } @field_order;
        die "Duplicate field '$field' will be mangled" if
            scalar(grep { $field eq $_ } $entry->fieldlist()) >= 2;
    }
    $entry->set_fieldlist([map { $entry->exists($_) ? ($_) : () } @field_order]);

    # Omit fields we don't want
    # TODO: controled per type or with other fields or regex matching
#    $entry->delete($_) for (@OMIT);

    # Force comma or no comma after last field
    my $str = $entry->print_s();
    $str =~ s[(})(\s*}\s*)$][$1,$2] if $COMMA;
    $str =~ s[(}\s*),(\s*}\s*)$][$1$2] if !$COMMA;
    print $str;
}

################

# Based on TeX::Encode and modified to use braces appropriate for BibTeX.
sub latex_encode
{
    use utf8;
    my ($str) = decode_html(@_);
    $str =~ s[\s*$][];
    $str =~ s[^\s*][];
    $str =~ s[\n{2,}][\n{\\par}\n]sg; # BibTeX eats whitespace
    $str =~ s[([<>])][\\ensuremath{$1}]sog;
    $str = unicode2tex($str);
#    $str =~ s[([^\x00-\x80])][\{@{[$TeX::Encode::LATEX_Escapes{$1} or
#             die "Unknown Unicode charater: $1 ", sprintf("0x%x", ord($1))]}\}]sg;
    return $str;
}

sub decode_html {
    my ($x) = @_;
    # HTML -> LaTeX Codes
    $x = decode_entities($x);
# #$%&~_^{}\\
#    print $TeX::Encode::LATEX_Reserved, "\n";
    #$x =~ s[([$TeX::Encode::LATEX_Reserved])][\\$1]sog;
    $x =~ s[([\#\$\%\&\~\_\^\{\}\\])][\\$1]sog;
    $x =~ s[<!--.*?-->][]sg;
    $x =~ s[<a [^>]*onclick="toggleTabs\(.*?\)">.*?</a>][]sg; # Science Direct
    $x =~ s[<a( .*?)?>(.*?)</a>][$2]sog;
    $x =~ s[<p(| [^>]*)>(.*?)</p>][$2\n\n]sg;
    $x =~ s[<par(| [^>]*)>(.*?)</par>][$2\n\n]sg;
    $x =~ s[<span style="font-family:monospace">(.*?)</span>][{\\tt $1}];
    $x =~ s[<span( .*)?>(.*?)</span>][$2]sg;
    $x =~ s[<i>(.*?)</i>][{\\it $1}]sog;
    $x =~ s[<italic>(.*?)</italic>][{\\it $1}]sog;
    $x =~ s[<em>(.*?)</em>][{\\em $1}]sog;
    $x =~ s[<strong>(.*?)</strong>][{\\bf $1}]sog;
    $x =~ s[<b>(.*?)</b>][{\\bf $1}]sog;
    $x =~ s[<sup>(.*?)</sup>][\\ensuremath{\^\\textrm{$1}}]sog;
    $x =~ s[<supscrpt>(.*?)</supscrpt>][\\ensuremath{\^\\textrm{$1}}]sog;
    $x =~ s[<sub>(.*?)</sub>][\\ensuremath{\_\\textrm{$1}}]sog;
    $x =~ s[<img src="http://www.sciencedirect.com/scidirimg/entities/([0-9a-f]+).gif".*?>][@{[chr(hex $1)]}]sg; # Science Direct
    return $x;
}

################

sub parse_bibtex {
    my ($bib_text) = @_;
    $bib_text =~ s/^\x{FEFF}//; # Remove Byte Order Mark

    my $entry = new Text::BibTeX::Entry;
    print "BIBTEXT:\n$bib_text\n" if $DEBUG;
    $entry->parse_s(encode('utf8', $bib_text), 0); # 1 for preserve values
    die "Can't parse BibTeX:\n$bib_text\n" unless $entry->parse_ok;

    # Parsing the bibtex converts it to utf8, so we have to decode it
    $entry->set_key(decode('utf8', $entry->key));
    for ($entry->fieldlist) { $entry->set($_, decode('utf8', $entry->get($_))) }

    return $entry;
}

sub update {
    my ($entry, $field, $fun) = @_;
    if ($entry->exists($field)) {
        $_ = $entry->get($field);
        &$fun();
        if (defined $_) { $entry->set($field, $_); }
        else { $entry->delete($field); }
    }
}
