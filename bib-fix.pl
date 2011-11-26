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

############
# Options
############
#
# Comma at end
# Key: Keep vs generate
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

# TODO:
#  abstract:
#  - paragraphs: no marker but often we get ".<Uperchar>" or "<p></p>"
#  - pass it through paragraph fmt
#  author as editors?
#  Put upper case words in {.} (e.g. IEEE)
#  detect fields that are already de-unicoded (e.g. {H}askell or $p$)
#  move copyright from abstract to copyright field
#END TODO

# TODO: omit type-regex field-regex (existing entry is in scope)

# Warn about non-four-digit year
# Omit:class/type
# Include:class/type
# no issn, no isbn
# SIGPLAN
# title-case after ":"
# Warn if first alpha after ":" is not capitalized
# Flag about whether to Unicode, HTML, or LaTeX encode
# purify_string

$main::VERSION=1.0;

# TODO: per type
# Doubles as field order
my @KNOWN_FIELDS = qw(
      author editor affiliation title
      howpublished booktitle journal volume number series jstor_issuetitle
      type jstor_articletype school institution location
      chapter pages articleno numpages
      edition month year issue_date jstor_formatteddate
      organization publisher address
      language isbn issn doi eid acmid url eprint bib_scrape_url
      note annote keywords abstract copyright);

my ($DEBUG, $GENERATE_KEY, $COMMA) = (0, 1, 1);
my %NO_ENCODE = map {($_,1)} ('doi', 'url', 'eprint', 'bib_scrape_url');
my %NO_COLLAPSE = map {($_,1)} ('note', 'annote', 'abstract');
my %RANGE = map {($_,1)} ('chapter', 'month', 'number', 'pages', 'volume', 'year');
my %OMIT = (); # per type (optional regex on value)
#my %OMIT_BLANK = (); # per type
#my @REQUIRE_FIELDS = (...); # per type (optional regex on value)
#my @RENAME

sub string_no_flag {
    my ($name, $HASH) = @_;
    ("$name=s" => sub { delete $HASH->{$_[1]} },
     "no-$name=s" => sub { $HASH->{$_[1]} = 1 });
}

sub string_flag {
    my ($name, $HASH) = @_;
    ("$name=s" => sub { $HASH->{$_[1]} = 1 },
     "no-$name=s" => sub { delete $HASH->{$_[1]} });
}

GetOptions(
    'field=s' => sub { push @KNOWN_FIELDS, $_[1] },
    'debug!' => \$DEBUG,
    #no-defaults
    'generate-keys!' => \$GENERATE_KEY,
    'comma!' => \$COMMA,
    string_no_flag('encode', \%NO_ENCODE),
    string_no_flag('collapse', \%NO_COLLAPSE), # Whether to collapse contingues whitespace
    string_flag('omit', \%OMIT)
    );

=head1 SYNOPSIS

bibscrape [options] <url> ...

=head2 OPTIONS

=item --omit=field

    Omit a particular field from the output.

=item --debug

    Print debug data (TODO: make it verbose and go to STDERR)

=cut

my $file = new Text::BibTeX::File "<-";

while (my $entry = new Text::BibTeX::Entry $file) {
    # TODO: $bib_text =~ s/^\x{FEFF}//; # Remove Byte Order Mark
    # Fix any unicode that is in the field values
    $entry->set_key(decode('utf8', $entry->key));
    $entry->set($_, decode('utf8', $entry->get($_)))
        for ($entry->fieldlist());

    # Doi field: remove "http://hostname/" or "DOI: "
    $entry->set('doi', $entry->get('url')) if (
        not $entry->exists('doi') and
        ($entry->get('url') || "") =~ m[^http://dx.doi.org/.*$]);
    update($entry, 'doi', sub { s[http://[^/]+/][]i; s[DOI:\s*][]ig; });

    # Page numbers: no "pp." or "p."
    # TODO: page fields
    # [][pages][pp?\.\s*][]ig;
    update($entry, 'pages', sub { s[pp?\.\s*][]ig; });

    # [][number]rename[issue][.+][$1]delete;
    # rename fields
    for (['issue', 'number'], ['keyword', 'keywords']) {
        # Fix broken field names (SpringerLink and ACM violate this)
        if ($entry->exists($_->[0]) and not $entry->exists($_->[1])) {
            $entry->set($_->[1], $entry->get($_->[0]));
            $entry->delete($_->[0]);
        }
    }

    # TODO: remove empty fields

    # Ranges: convert "-" to "--"
    # TODO: option for numeric range
    # TODO: might misfire if "-" doesn't represent a range, Common for tech report numbers
    for my $key ('chapter', 'month', 'number', 'pages', 'volume', 'year') {
        update($entry, $key, sub { s[\s*-+\s*][--]ig; });
        update($entry, $key, sub { s[n/a--n/a][]ig; $_ = undef if $_ eq "" });
        update($entry, $key, sub { s[\b(\w+)--\1\b][$1]ig; });
    }

    # TODO: ISBN: 10 vs 13 vs native, dash vs no-dash vs native
    # TODO: ISSN: Print vs electronic vs native, dash vs no-dash vs native
    # TODO: Keywords: ';' vs ','

    # TODO: Title Capticalization: Initialisms, After colon, list of proper names
    # TODO: Author, Editor, Affiliation: List of renames
# Booktitle, Journal, Publisher*, Series, School, Institution, Location*, Edition*, Organization*, Publisher*, Address*, Language*:
#  List of renames (regex?)

    # Don't include pointless URLs to publisher's page
    # [][url][http://dx.doi.org/][];
    # TODO: via Omit if matches
    # TODO: omit if ...
    update($entry, 'url', sub {
        $_ = undef if m[^(http://dx.doi.org/
                         |http://doi.acm.org/
                         |http://portal.acm.org/citation.cfm
                         |http://www.jstor.org/stable/
                         |http://www.sciencedirect.com/science/article/)]x; } );
    # TODO: via omit if empty
    update($entry, 'note', sub { $_ = undef if $_ eq "" });
    # TODO: add $doi to omit if matches
    # [][note][$doi][]
    # regex delete if looks like doi
    # Fix Springer's use of 'note' to store 'doi'
    update($entry, 'note', sub { $_ = undef if $_ eq ($entry->get('doi') or "") });

    # Collapse spaces and newlines
    $NO_COLLAPSE{$_} or update($entry, $_, sub { $_ =~ s/\s+/ /sg; }) for $entry->fieldlist();

    # Eliminate Unicode but not for doi and url fields (assuming \usepackage{url})
    for my $field ($entry->fieldlist()) {
        warn "Undefined $field" unless defined $entry->get($field);
        $entry->set($field, latex_encode($entry->get($field)))
            unless exists $NO_ENCODE{$field};
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


    # Omit fields we don't want
    # TODO: controled per type or with other fields or regex matching
    # omit if empty
    $entry->exists($_) and $entry->delete($_) for (keys %OMIT);

    # Put fields in a standard order.
    for my $field ($entry->fieldlist()) {
        die "Unknown field: $field.\n" unless grep { $field eq $_ } @KNOWN_FIELDS;
        die "Duplicate field '$field' will be mangled" if
            scalar(grep { $field eq $_ } $entry->fieldlist()) >= 2;
    }
    $entry->set_fieldlist([map { $entry->exists($_) ? ($_) : () } @KNOWN_FIELDS]);

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
    my ($str) = @_;

    # HTML -> LaTeX Codes
    $str = decode_entities($str);
    #$str =~ s[\_(.)][\\ensuremath{\_{$1}}]isog; # Fix for IOS Press
    $str =~ s[([\#\$\%\&\~\_\^\{\}\\])][\\$1]sog;
    $str =~ s[<!--.*?-->][]sg;
    $str =~ s[<a [^>]*onclick="toggleTabs\(.*?\)">.*?</a>][]isg; # Science Direct
    $str =~ s[<a( .*?)?>(.*?)</a>][$2]isog;
    $str =~ s[<p(| [^>]*)>(.*?)</p>][$2\n\n]isg;
    $str =~ s[<par(| [^>]*)>(.*?)</par>][$2\n\n]isg;
    $str =~ s[<span style="font-family:monospace">(.*?)</span>][{\\tt $1}]i;
    $str =~ s[<span( .*)?>(.*?)</span>][$2]isg;
    $str =~ s[<i>(.*?)</i>][{\\it $1}]isog;
    $str =~ s[<italic>(.*?)</italic>][{\\it $1}]isog;
    $str =~ s[<em>(.*?)</em>][{\\em $1}]isog;
    $str =~ s[<strong>(.*?)</strong>][{\\bf $1}]isog;
    $str =~ s[<b>(.*?)</b>][{\\bf $1}]isog;
    $str =~ s[<sup>(.*?)</sup>][\\ensuremath{\^\\textrm{$1}}]isog;
    $str =~ s[<supscrpt>(.*?)</supscrpt>][\\ensuremath{\^\\textrm{$1}}]isog;
    $str =~ s[<sub>(.*?)</sub>][\\ensuremath{\_\\textrm{$1}}]isog;
    $str =~ s[<img src="http://www.sciencedirect.com/scidirimg/entities/([0-9a-f]+).gif".*?>][@{[chr(hex $1)]}]isg; # Fix for Science Direct
    $str =~ s[<!--title-->$][]isg; # Fix for Science Direct

    # Misc fixes
    $str =~ s[\s*$][]; # remove trailing whitespace
    $str =~ s[^\s*][]; # remove leading whitespace
    $str =~ s[\n{2,} *][\n{\\par}\n]sg; # BibTeX eats whitespace so convert "\n\n" to paragraph break
    $str =~ s[([<>])][\\ensuremath{$1}]sog;
    $str = unicode2tex($str);
    return $str;
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
