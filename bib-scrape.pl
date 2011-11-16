#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use WWW::Mechanize;
use Text::BibTeX;
use Text::BibTeX qw(:subs);
use Text::BibTeX::Value;
use TeX::Encode;
use TeX::Unicode;
use HTML::Entities;
use Encode;

use Text::RIS;
use Text::GoogleScholar;
use Text::BibTeX::Months;

use Getopt::Long qw(:config auto_version auto_help);

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
my ($BIBTEX, $DEBUG, $KEEP_KEYS, @OMIT);

GetOptions('bibtex!' => \$BIBTEX, 'debug!' => \$DEBUG, 'keep-keys!' => \$KEEP_KEYS,
    'omit=s' => \@OMIT);
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
#  get PDF
#  abstract:
#  - paragraphs: no marker but often we get ".<Uperchar>" or "<p></p>"
#  author as editors?
#  Put upper case words in {.} (e.g. IEEE)
#  detect fields that are already de-unicoded (e.g. {H}askell or $p$)
#  follow jstor links to original publisher
#  add abstract to jstor
#END TODO

#my %latex_fixes = (
#    "\x{2a7d}" => "\$\\leqslant\$",
#    "\x{2a7e}" => "\$\\geqslant\$",
#    "\x{204e}" => "\textasteriskcentered", # Not a perfect match but close enough
#    "\x{2113}" => "\$\\ell\$",
#    "\x{03bb}" => "\$\\lambda\$",
#    "\x{039b}" => "\$\\Lambda\$",
#    );

#$TeX::Encode::LATEX_Escapes{$_} = $latex_fixes{$_} for keys %latex_fixes;
#
# \ensuremath{FOO} is better than $FOO$
#for (keys %TeX::Encode::LATEX_Escapes) {
#    $TeX::Encode::LATEX_Escapes{$_} =~ s[^\$(.*)\$$][\\ensuremath{$1}];
#}

my $mech;

my @entries;

if ($BIBTEX) {
    my $file = new Text::BibTeX::File "<-";
    while (my $entry = new Text::BibTeX::Entry $file) {
#    bib_scrape_url = dx.doi if doi and not bib_scrape_url
#    $x->exists('doi') ? "http://dx.doi.org/".doi_clean($x->get('doi')) :
#        $x->exists('bib-scrape-url') ? $x->get('bib-scrape-url') : warn "";
#    push @entries, ...;
        print $entry, "\n";
        push @entries, $entry;
    }
}

for (@ARGV) {
    my $entry = new Text::BibTeX::Entry;
    $entry->set('bib_scrape_url', $_);
    push @entries, $entry;
}

for my $old_entry (@entries) {
    my $url = $old_entry->get('bib_scrape_url');
    print $old_entry->print_s() and next unless $url;
    $mech = WWW::Mechanize->new(autocheck => 1);
    $mech->add_handler("request_send",  sub { shift->dump; return }) if $DEBUG;
    $mech->add_handler("response_done", sub { shift->dump; return }) if $DEBUG;
    $mech->agent_alias('Windows IE 6');
    $mech->get($url);

    my $entry = parse($mech);
    $entry->set('bib_scrape_url', $url);
    print encode('utf8', $entry->print_s());
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

################

sub domain { $mech->uri()->authority() =~ m[^(|.*\.)\Q$_[0]\E]i; }

sub parse {
    if (domain('acm.org')) { parse_acm(@_); }
    elsif (domain('sciencedirect.com')) { parse_science_direct(@_); }
    elsif (domain('springerlink.com')) { parse_springerlink(@_); }
    elsif (domain('journals.cambridge.org')) { parse_cambridge_university_press(@_); }
    elsif (domain('computer.org')) { parse_ieee_computer_society(@_); }
    elsif (domain('jstor.org')) { parse_jstor(@_); }
    elsif (domain('iospress.metapress.com')) { parse_ios_press(@_); }
    elsif (domain('ieeexplore.ieee.org')) { parse_ieeexplore(@_); }
    elsif (domain('onlinelibrary.wiley.com')) {parse_wiley(@_); }
    elsif (domain('oxfordjournals.org')) { parse_oxford_journals(@_); }
    else { die "Unknown URI: " . $mech->uri(); }
}

sub parse_acm {
    my ($mech) = @_;

    # BibTeX
    my ($url) = $mech->find_link(text=>'BibTeX')->url()
        =~ m[navigate\('(.*?)'];
    $mech->get($url);
    my ($i, $cont) = (1, undef);
    # Try to avoid SIGPLAN Notices
    while ($mech->find_link(text => 'download', n => $i)) {
        $mech->follow_link(text => 'download', n => $i);
        $cont = $mech->content()
            unless defined $cont and
            $mech->content() =~ m[journal = \{?SIGPLAN Not]i;
        $mech->back();
        $i++;
    }
    $cont =~ s[(\@.*) ][$1]; # Prevent keys with spaces
    my $entry = parse_bibtex($cont);

    $mech->back();

    # Un-abbreviated journal title, but avoid spurious "journal" when
    # proceedings are published in SIGPLAN Not.
    my $html = Text::GoogleScholar::parse($mech->content())->bibtex();
    $entry->set('journal', $html->get('journal')) if $entry->exists('journal');

    $entry->set('author', $html->get('author')) if ($entry->exists('author'));

    $entry->set('title', $mech->content() =~
                m[<h1 class="mediumb-text".*?><strong>(.*?)</strong></h1>])
        if $entry->exists('title');

    # Abstract
    my ($abstr_url) = $mech->content() =~ m[(tab_abstract.*?)\'];
    $mech->get($abstr_url);
    if (my ($abstr) = $mech->content() =~
        m[<div style="display:inline">((?:<par>|<p>)?.+?(?:</par>|</p>)?)</div>]) {
        # Fix the double HTML encoding of the abstract (Bug in ACM?)
        $entry->set('abstract', decode_entities($abstr));
    }

    return $entry;
}

sub parse_science_direct {
    my ($mech) = @_;

    # Find the title and reverse engineer the Unicode
    my ($title) = $mech->content() =~ m[<div\b[^>]*\bclass="articleTitle.*?>\s*(.*?)\s*</div>]s;
    my ($abst) = $mech->content() =~ m[>Abstract</h3>\s*(.*?)\s*</div>];

    $mech->follow_link(text => 'Export citation');

    $mech->submit_form(with_fields => {
        'format' => 'cite', 'citation-type' => 'BIBTEX'});
    my $entry = parse_bibtex($mech->content());
    $entry->set('title', $title);
    $entry->set('abstract', $abst);
    $mech->back();

    $mech->submit_form(with_fields => {
        'format' => 'cite-abs', 'citation-type' => 'RIS'});
    my $f = Text::RIS::parse(decode('utf8', $mech->content()))->bibtex();
    $entry->set('author', $f->get('author'));
    $entry->set('month', $f->get('month'));
    $entry->delete('keywords');
    $entry->set('keywords', $f->get('keywords')) if $f->get('keywords');
# TODO: editor

    return $entry;
}

sub parse_springerlink {
    my ($mech) = @_;
# TODO: handle books
    $mech->follow_link(url_regex => qr[/export-citation/])
        unless $mech->uri() =~ m[/export-citation/];

    $mech->submit_form(
        with_fields => {
            'ctl00$ContentPrimary$ctl00$ctl00$Export' => 'AbstractRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$CitationManagerDropDownList'
                => 'BibTex'},
        button => 'ctl00$ContentPrimary$ctl00$ctl00$ExportCitationButton');
    my $entry = parse_bibtex(decode('utf8', $mech->content()));
    $mech->back();

    $mech->submit_form(
        with_fields => {
            'ctl00$ContentPrimary$ctl00$ctl00$Export' => 'AbstractRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$CitationManagerDropDownList' => 'EndNote'},
        button => 'ctl00$ContentPrimary$ctl00$ctl00$ExportCitationButton');
    my $f = Text::RIS::parse($mech->content())->bibtex();
    ($f->exists($_) && $entry->set($_, $f->get($_))) for ('doi', 'month', 'issn', 'isbn');
    # TODO: remove "Summary" from abstract

    return $entry;
}

sub parse_cambridge_university_press {
    my ($mech) = @_;

    $mech->follow_link(text => 'Export Citation');
    $mech->submit_form(form_name => 'exportCitationForm',
                       fields => {'Download' => 'Download',
                                  'displayAbstract' => 'Yes',
                                  'format' => 'BibTex'});
    my $entry = parse_bibtex($mech->content());
    $mech->back(); $mech->back();

    my ($abst) = $mech->content() =~ m[>Abstract</.*?><p>(<p>.*?</p>)\s*</p>]s;
    $entry->set('abstract', $abst) if $abst;

    $entry->set('title',
                join(": ",
                     map { $_ ne "" ? $_ : () }
                     ($mech->content() =~ m[<h2><font.*?>(.*?)</font></h2>]sg,
                      $mech->content() =~ m[</h3>\s*<h3>(.*?)(?=</h3>)]sg
                     )));
    $entry->set('title', $mech->content() =~
                m[<div id="codeDisplayWrapper">\s*<div.*?>\s*<div.*?>(.*?)</div>])
        unless $entry->get('title');

    update($entry, 'doi', sub { $_ = undef if $_ eq "null" });

    return $entry;
    # TODO: fix case of authors
}

sub parse_ieee_computer_society {
    my ($mech) = @_;
    $mech->follow_link(text => 'BibTex');
    my $entry = parse_bibtex($mech->content());
    update($entry, 'volume', sub { $_ = undef if $_ eq "0" });
    return $entry;
    # TODO: volume is 0?
}

sub parse_ieeexplore {
    my ($mech, $fields) = @_;
    my ($record) = $mech->content() =~
        m[<span *id="recordId" *style="display:none;">(\d*)</span>];

    # Ick, work around javascript by hard coding the URL
    $mech->get("http://ieeexplore.ieee.org/xpl/downloadCitations?".
               "recordIds=$record&".
               "fromPageName=abstract&".
               "citations-format=citation-abstract&".
               "download-format=download-bibtex");
    my $cont = $mech->content();
    print $cont, "\n";
    $cont =~ s/<br>//gi;
    $cont =~ s/month=([^,\.{}"]*?)\./month=$1/;
    return parse_bibtex($cont);
}

sub parse_jstor {
    my ($mech) = @_;
    $mech->follow_link(text => 'Export Citation');

    # Ick, we have to get around the javascript
    $mech->form_with_fields('suffix');
    my $suffix = $mech->value('suffix');
    $mech->post("http://www.jstor.org/action/downloadSingleCitation",
                {'singleCitation'=>'true', 'suffix'=>$suffix,
                 'include'=>'abs', 'format'=>'bibtex', 'noDoi'=>'yesDoi'});

    my $cont = $mech->content();
    $cont =~ s[\@comment{.*$][]gm; # hack to get around comments
    $cont =~ s[JSTOR CITATION LIST][]g; # hack to avoid junk chars
    my $entry = parse_bibtex($cont);
    $entry->set('doi', $suffix);
    my ($month) = ($entry->get('jstor_formatteddate') =~ m[^(.*?)( \d\d?)?, \d\d\d\d$]);
    $entry->set('month', $month) if defined $month;
    # TODO: remove empty abstract

    $mech->back(); $mech->back();
    $entry->set('title', $mech->content() =~ m[><div class="hd title">(.*?)</div>]);
    return $entry;
}

sub parse_ios_press {
    my ($mech) = @_;

    $mech->follow_link(text => 'RIS');
    my $f = Text::RIS::parse(decode('utf8', $mech->content()))->bibtex();
    my $entry = parse_bibtex("\@" . $f->type . " {unknown_key,}");
    # TODO: missing items?
    for ('journal', 'title', 'volume', 'number', 'abstract', 'pages',
         'author', 'year', 'month', 'doi') {
        $entry->set($_, $f->get($_)) if $f->exists($_);
    }

    $mech->back();

    my ($pub) = ($mech->content() =~ m[>Publisher</td><td.*?>(.*?)</td>]i);
    $entry->set('publisher', $pub) if defined $pub;
    my ($issn) = ($mech->content() =~ m[>ISSN</td><td.*?>(.*?)</td>]i);
    $issn =~ s[<br/?>][ ];
    $entry->set('issn', $issn) if defined $issn;
    my ($isbn) = ($mech->content() =~ m[>ISBN</td><td.*?>(.*?)</td>]i);
    $entry->set('isbn', $isbn) if defined $isbn;

    return $entry;
}

sub parse_wiley {
    my ($mech) = @_;
    $mech->follow_link(text => 'Export Citation for this Article');
    $mech->submit_form(with_fields => {
        'fileFormat' => 'BIBTEX', 'hasAbstract' => 'CITATION_AND_ABSTRACT'});
    my $entry = parse_bibtex(decode('utf8', $mech->content()));

    $mech->back(); $mech->back();
    $entry->set('title', $mech->content() =~ m[<h1 class="articleTitle">(.*?)</h1>]s);
    $entry->set('abstract', $mech->content() =~ m[<div class="para">(.*?)</div>]s);

#    update($entry, 'abstract', sub { s[^\s*Abstract\s+][] });
    update($entry, 'abstract',
           sub { s[Copyright \x{00a9} \d\d\d\d John Wiley \& Sons, Ltd\.\s*$][] });
    update($entry, 'abstract',
           sub { s[\x{00a9} \d\d\d\d Wiley Periodicals, Inc\. Random Struct\. Alg\., \d\d\d\d\s*$][] });
    return $entry;
}

sub parse_oxford_journals {
    my ($mech) = @_;

    my $html = Text::GoogleScholar::parse($mech->content())->bibtex();
    my $entry = parse_bibtex("\@article{unknown_key,}");

    $html->exists($_) and $entry->set($_, $html->get($_)) for (qw(
      author editor affiliation title
      howpublished booktitle journal volume number series
      type school institution location
      chapter pages
      edition month year
      organization publisher address
      language isbn issn doi url
      note annote keywords abstract copyright));

    my ($year, $month) = ($mech->content() =~
                          m[<meta +content="(\d+)-(\d+)-\d+" +name="DC.Date" */>]i);
    $entry->set('year', $year);
    $entry->set('month', num2month($month)->[1]);

    $entry->set('publisher', ($mech->content() =~
                              m[<meta +content="(.*?)" name="DC.Publisher" */>]i));
#    $entry->set('address', 'Oxford, UK');
    update($entry, 'issn', sub { s[ *; *][/]g; });

    return $entry;
}
