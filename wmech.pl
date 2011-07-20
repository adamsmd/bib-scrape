#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use WWW::Mechanize;
use Text::BibTeX;
use Text::BibTeX::Value;
use HTML::HeadParser;
use TeX::Encode;
use HTML::Entities;
use Encode;

use Text::RIS;
use Text::BibTeX::Months;

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

# \ensuremath{FOO} is better than $FOO$
for (keys %TeX::Encode::LATEX_Escapes) {
    $TeX::Encode::LATEX_Escapes{$_} =~ s[^\$(.*)\$$][\\ensuremath{$1}];
}

sub DEBUG() { 0; }

my $mech;

for my $url (@ARGV) {
    $mech = WWW::Mechanize->new(autocheck => 1);
    $mech->add_handler("request_send",  sub { shift->dump; return }) if DEBUG;
    $mech->add_handler("response_done", sub { shift->dump; return }) if DEBUG;
    $mech->agent_alias('Windows IE 6');
    $mech->get($url);

    my $entry = parse($mech);

    # Doi field: remove "http://hostname/" or "DOI: "
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

    # Ranges: convert "-" to "--"
    # TODO: might misfire if "-" doesn't represent a range, Common for tech report numbers
    for my $key ('chapter', 'month', 'number', 'pages', 'volume', 'year') {
        update($entry, $key, sub { s[\s*-+\s*][--]ig; });
        # TODO: single element range as x not x--x
    }

    # Don't include pointless URLs to publisher's page
    update($entry, 'url', sub {
        $_ = undef if m[^(http://dx.doi.org/
                         |http://doi.acm.org/
                         |http://portal.acm.org/citation.cfm
                         |http://www.jstor.org/stable/
                         |http://www.sciencedirect.com/science/article/)]x; } );
    update($entry, 'note', sub { $_ = undef if $_ eq "" });
    update($entry, 'note', sub { $_ = undef if $_ eq ($entry->get('doi') or "") });

    # Generate an entry key
    # TODO: Formats: author/editor1.last year title/journal.abbriv
    # TODO: Key may fail on unicode names? Remove doi?
    my ($name) = ($entry->names('author'), $entry->names('editor'));
        #$organization, or key
    if ($name and $entry->exists('year')) {
        ($name) = join("", $name->part('last'));
        $entry->set_key($name . ':' . $entry->get('year') .
            ($entry->exists('doi') ? ":" . $entry->get('doi') : ""));
    }

    # Eliminate Unicode but not for doi and url fields (assuming \usepackage{url})
    for my $field ($entry->fieldlist()) {
        $entry->set($field, latex_encode($entry->get($field)))
            unless $field eq 'doi' or $field eq 'url'
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
    my @field_order = qw(
      author editor affiliation title
      howpublished booktitle journal volume number series jstor_issuetitle
      type jstor_articletype school institution location
      chapter pages articleno numpages
      edition month year issue_date jstor_formatteddate
      organization publisher address
      language isbn issn doi eid acmid url eprint
      note annote keywords abstract copyright);
    for my $field ($entry->fieldlist()) {
        die "Unknown field: $field.\n" unless grep { $field eq $_ } @field_order;
        die "Duplicate field '$field' will be mangled" if
            scalar(grep { $field eq $_ } $entry->fieldlist()) >= 2;
    }
    $entry->set_fieldlist([map { $entry->exists($_) ? ($_) : () } @field_order]);

    # Force comma after last field to make editing easier
    my $str = $entry->print_s();
    $str =~ s[}(\s*}\s*)$][\},$1];
    print $str;
}

################

# Based on TeX::Encode and modified to use braces appropriate for BibTeX.
sub latex_encode
{
    use utf8;
    my ($str) = @_;
    $str = decode_entities($str);
    $str =~ s[([$TeX::Encode::LATEX_Reserved])][\\$1]sog;
    $str =~ s[<i>(.*?)</i>][{\\it $1}]sog; # HTML -> LaTeX Codes
    $str =~ s[<em>(.*?)</em>][{\\em $1}]sog;
    $str =~ s[<sup>(.*?)</sup>][\\ensuremath{\^\\textrm{$1}}]sog;
    $str =~ s[<sub>(.*?)</sub>][\\ensuremath{\_\\textrm{$1}}]sog;
    $str =~ s[([<>])][\\ensuremath{$1}]sog;
    $str =~ s[([^\x00-\x80])][\{$TeX::Encode::LATEX_Escapes{$1}\}]sg;
    return $str;
}

################

sub parse_bibtex {
    my ($bib_text) = @_;
    $bib_text =~ s/^\x{FEFF}//; # Remove Byte Order Mark

    my $entry = new Text::BibTeX::Entry;
    print "BIBTEXT:\n$bib_text\n" if DEBUG;
    $entry->parse_s(encode('utf8', $bib_text), 0); # 1 for preserve values
    die "Can't parse BibTeX:\n$bib_text\n" unless $entry->parse_ok;

    # Parsing the bibtex converts it to utf8, so we have to decode it
    $entry->set_key(decode('utf8', $entry->key));
    for ($entry->fieldlist) { $entry->set($_, decode('utf8', $entry->get($_))) }

    return $entry;
}

sub domain { $mech->uri()->authority() =~ m[^(|.*\.)\Q$_[0]\E]i; }

sub update {
    my ($entry, $field, $fun) = @_;
    if ($entry->exists($field)) {
        $_ = $entry->get($field);
        &$fun();
        if (defined $_) { $entry->set($field, $_); }
        else { $entry->delete($field); }
    }
}

sub meta_tag {
    my ($name) = @_;
    my $p = new HTML::HeadParser;
    $p->parse($mech->content());
    return $p->header('X-Meta-' . $name);
}

################

sub parse {
    if (domain('acm.org')) { parse_acm(@_); }
    elsif (domain('sciencedirect.com')) { parse_science_direct(@_); }
    elsif (domain('springerlink.com')) { parse_springerlink(@_); }
    elsif (domain('journals.cambridge.org')) {
        parse_cambridge_university_press(@_);
    }
    elsif (domain('computer.org')) { parse_ieee_computer_society(@_); }
    elsif (domain('jstor.org')) { parse_jstor(@_); }
    elsif (domain('iospress.metapress.com')) { parse_ios_press(@_); }
    elsif (domain('ieeexplore.ieee.org')) { parse_ieeexplore(@_); }
    elsif (domain('onlinelibrary.wiley.com')) {parse_wiley(@_); }
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
    $entry->set('journal', meta_tag('citation_journal_title'))
        if $entry->exists('journal');

    if ($entry->exists('author')) {
        my @x = meta_tag('citation_authors');
        $x[0] =~ s[;][ and ]g;
        $x[0] =~ s[  +][ ]g;
        $entry->set('author', $x[0]);
    }

    $entry->set('title', $mech->content() =~
                m[<h1 class="mediumb-text".*?><strong>(.*?)</strong></h1>])
        if $entry->exists('title');

    # Abstract
    my ($abstr_url) = $mech->content() =~ m[(tab_abstract.*?)\'];
    $mech->get($abstr_url);
    $entry->set('abstract', $mech->content() =~
                m[<div style="display:inline">(?:<par>|<p>)?(.+?)(?:</par>|</p>)?</div>]);
    # Fix the double HTML encoding of the abstract (Bug in ACM?)
    $entry->set('abstract', decode_entities($entry->get('abstract')));

    return $entry;
}

sub parse_science_direct {
    my ($mech) = @_;

    $mech->follow_link(text => 'Export citation');

    $mech->submit_form(with_fields => {
        'format' => 'cite', 'citation-type' => 'BIBTEX'});
    my $entry = parse_bibtex($mech->content());
    $mech->back();

    $mech->submit_form(with_fields => {
        'format' => 'cite-abs', 'citation-type' => 'RIS'});
    my $f = Text::RIS::parse($mech->content())->bibtex();
    $entry->set('author', $f->get('author'));
    $entry->set('month', $f->get('month'));
    $entry->set('abstract', $f->get('abstract'));
    $entry->delete('keywords');
    $entry->set('keywords', $f->get('keywords'));
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

    my ($abst) = $mech->content() =~ m[>Abstract</.*?><p><p>(.*?)</p>]s;
    $entry->set('abstract', $abst) if $abst;
    update($entry, 'doi', sub { $_ = undef if $_ eq "null" });

    return $entry;
    # TODO: fix authors
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
    my ($month) = ($entry->get('jstor_formatteddate') =~ m[^(.*)( \d\d?), \d\d\d\d$]);
    $entry->set('month', $month) if defined $month;
    # TODO: remove empty abstract
    return $entry;
}

sub parse_ios_press {
    my ($mech) = @_;

    $mech->follow_link(text => 'RIS');
    my $f = Text::RIS::parse($mech->content())->bibtex();
    my $entry = parse_bibtex("\@" . $f->type . " {X,}");
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
    my ($mech, $fields) = @_;
    $mech->follow_link(text => 'Export Citation for this Article');
    $mech->submit_form(with_fields => {
        'fileFormat' => 'BIBTEX', 'hasAbstract' => 'CITATION_AND_ABSTRACT'});
    my $entry = parse_bibtex(decode('utf8', $mech->content()));
    update($entry, 'abstract', sub { s[^\s*Abstract\s+][] });
    update($entry, 'abstract',
           sub { s[ Copyright . \d\d\d\d John Wiley \& Sons, Ltd\.$][] });
    return $entry;
}
