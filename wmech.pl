#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use WWW::Mechanize;
use Text::BibTeX;
use Text::BibTeX::Value;
use HTML::HeadParser;
use TeX::Encode;
use Encode;

# TODO:
#  comma after last field
#  adjust key
#  get PDF
#  abstract:
#  - paragraphs: no marker but often we get ".<Uperchar>" or "<p></p>"
#  - HTML encoding?
#  titles: superscript (r6rs, r5rs), &part;
#  author as editors?


sub DEBUG() { 0; }

my $mech;
my $entry;

my @months = (
    undef,
    [Text::BibTeX::BTAST_MACRO, 'jan'],
    [Text::BibTeX::BTAST_MACRO, 'feb'],
    [Text::BibTeX::BTAST_MACRO, 'mar'],
    [Text::BibTeX::BTAST_MACRO, 'apr'],
    [Text::BibTeX::BTAST_MACRO, 'may'],
    [Text::BibTeX::BTAST_MACRO, 'jun'],
    [Text::BibTeX::BTAST_MACRO, 'jul'],
    [Text::BibTeX::BTAST_MACRO, 'aug'],
    [Text::BibTeX::BTAST_MACRO, 'sep'],
    [Text::BibTeX::BTAST_MACRO, 'oct'],
    [Text::BibTeX::BTAST_MACRO, 'nov'],
    [Text::BibTeX::BTAST_MACRO, 'dec']);

my %months = (
    $months[1]->[1] => $months[1],
    'january' => $months[1],
    $months[2]->[1] => $months[2],
    'february' => $months[2],
    $months[3]->[1] => $months[3],
    'march' => $months[3],
    $months[4]->[1] => $months[4],
    'april' => $months[4],
    $months[5]->[1] => $months[5],
    'may' => $months[5],
    $months[6]->[1] => $months[6],
    'june' => $months[6],
    $months[7]->[1] => $months[7],
    'july' => $months[7],
    $months[8]->[1] => $months[8],
    'august' => $months[8],
    $months[9]->[1] => $months[9],
    'september' => $months[9],
    'sept' => $months[9],
    $months[10]->[1] => $months[10],
    'october' => $months[10],
    $months[11]->[1] => $months[11],
    'november' => $months[11],
    $months[12]->[1] => $months[12],
    'december' => $months[12]);

for my $i (keys %months) {
    Text::BibTeX::add_macro_text($i, $months{$i}[1]);
}

#Text::BibTeX::Bib::month_names

#ABST		Abstract
#INPR		In Press
#JFULL		Journal (full)
#SER		Serial (Book, Monograph)
#THES	phdthesis/mastersthesis	Thesis/Dissertation

my %ris_types = (
    'BOOK', 'book',
    'CONF', 'proceedings',
    'CHAP', 'inbook',
    'CHAPTER', 'inbook',
    'INCOL', 'incollection',
    'JOUR', 'journal',
    'MGZN', 'article',
    'PAMP', 'booklet',
    'RPRT', 'techreport',
    'REP', 'techreport',
    'UNPB', 'unpublished');

sub parse_bibtex {
    my ($text) = @_;
    my $bib_text = decode('utf8', $text);
    $bib_text =~ s/^\x{FEFF}//; # Remove Byte Order Mark

    $entry = new Text::BibTeX::Entry;
    print "BIBTEXT:\n$bib_text\n" if DEBUG;
    $entry->parse_s($bib_text, 0); # 1 for preserve values
#    $entry = new Text::BibTeX::Entry($bib_text); # macros: pass "$bib_text, 1"
    die "Can't parse BibTeX" unless $entry->parse_ok;
    return $entry;
}

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
    # TODO: single element range as x not x-x
    # Ranges: convert "-" to "--"
    # TODO: might misfire if "-" doesn't represent a range
    #  Common for tech report numbers
    for my $key ('chapter', 'month', 'number', 'pages', 'volume', 'year') {
        update($entry, $key, sub { s[\s*-+\s*][--]ig; });
    }

    # Don't include pointless URLs to publisher's page
    update($entry, 'url', sub {
        $_ = undef if m[^(http://dx.doi.org/
                         |http://doi.acm.org/
                         |http://www.sciencedirect.com/science/article/)]x; } );
    update($entry, 'note', sub { $_ = undef if $_ eq "" });
    update($entry, 'note', sub { $_ = undef if $_ eq ($entry->get('doi') or "") });
    update($entry, 'issue', sub { # Broken SpringerLink BibTeX
        unless ($entry->exists('number')) {
            $entry->set('number', $_);
            $_ = undef;
        }});

    # \textquotedblleft -> ``
    # \textquoteleft -> `
    # etc.
    # TODO: detect fields that are already de-unicoded (e.g. {H}askell or $p$)

    # Eliminate Unicode
    for my $field ($entry->fieldlist()) {
        $entry->set($field, latex_encode(decode('utf8', $entry->get($field))))
            # But not for doi and url fields (assuming \usepackage{url})
            unless $field eq 'doi' or $field eq 'url'
    }

    # month abbriv: jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec
    #  ACM: {April}
    # TODO: breaks on: "Apr." -> apr # {.}
    update($entry, 'month', # Must be after field encoding
           sub { $_ = new Text::BibTeX::Value(
                     map { $months{lc $_}
                           or [Text::BibTeX::BTAST_STRING, $_] }
                     split qr[\b]) });

    # TODO: Generate standard key name: author/editor1.last year title/journal.abbriv
    # TODO: Put upper case words in {.} (e.g. IEEE)

    print $entry->print_s();
}

################

# Copied from TeX::Encode and modified to use braces appropriate for BibTeX.
sub latex_encode
{
    use utf8;
    my ($str) = @_;
    $str =~ s/([$TeX::Encode::LATEX_Reserved])/\\$1/sog;
    $str =~ s/([<>])/\$$1\$/sog;
    $str =~ s/([^\x00-\x80])/\{$TeX::Encode::LATEX_Escapes{$1}\}/sg;
    return $str;
}

################

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

sub parse_ris {
    my ($text) = @_;
    $text =~ s/^\x{FEFF}//; # Remove Byte Order Mark

    my $ris = {}; # {key, [string]}
    my $last_key = "";
    my @lines = (split("\n", $text));
    for my $line (@lines ) { #(split("\n", $text))) {
        $line =~ s[\r|\n][]g;
        my ($key, $val) = $line =~ m[^([A-Z][A-Z0-9]|DOI)  - *(.*?) *$];
        if (defined $key) { push @{$ris->{$key}}, $val; $last_key = $key; }
        elsif ("" ne $line) {
            my $list = $ris->{$last_key};
            @$list[$#$list] .= "\n" . $line;
        } else {} # blank line
    }
    $ris;
}

sub ris_author { join(" and ", map { s[(.*),(.*),(.*)][$1,$3,$2];
                                     m[[^, ]] ? $_ : (); } @_); }

sub ris_to_bib {
    my ($ris) = @_;
    my $fields = {};

    $fields->{'author'} = ris_author(@{$ris->{'A1'} || $ris->{'AU'} || []});
    $fields->{'editor'} = ris_author(@{$ris->{'A2'} || $ris->{'ED'} || []});
    $fields->{'keywords'} = join " ; ", @{$ris->{'KW'}} if $ris->{'KW'};
    $fields->{'url'} = join " ; ", @{$ris->{'UR'}} if $ris->{'UR'};

    for (keys %$ris) { $ris->{$_} = join "", @{$ris->{$_}} }

    my $doi = qr[^(\s*doi:\s*\w+\s+)?(.*)$]s;

    # TODO: flattening
    $fields->{'*type*'} = exists $ris_types{$ris->{'TY'}} ?
        $ris_types{$ris->{'TY'}} :
        (print STDERR "Unknown RIS TY: $ris->{'TY'}. Using misc.\n" and 'misc');
    #ID: ref id
    $fields->{'title'} = $ris->{'T1'} || $ris->{'TI'} || $ris->{'CT'} || (
        ($ris->{'TY'} eq 'BOOK' || $ris->{'TY'} eq 'UNPB') && $ris->{'BT'});
    $fields->{'booktitle'} = $ris->{'T2'} || (
        !($ris->{'TY'} eq 'BOOK' || $ris->{'TY'} eq 'UNPB') && $ris->{'BT'});
    $fields->{'series'} = $ris->{'T3'}; # check
    #A3: author series
    #A[4-9]: author (undocumented)
    my ($year, $month, $day) = split m[/|-], ($ris->{'PY'} || $ris->{'Y1'});
    $fields->{'year'} = $year;
    $fields->{'month'} = $months[$month]->[1] if $month;
    $fields->{'day'} = $day;
    #Y2: date secondary
    ($ris->{'N1'} || $ris->{'AB'} || $ris->{'N2'} || "") =~ $doi;
    $fields->{'abstract'} = $2 if length($2);
    #RP: reprint status (too complex for what we need)
    $fields->{'journal'} = ($ris->{'JF'} || $ris->{'JO'} || $ris->{'JA'} ||
                            $ris->{'J1'} || $ris->{'J2'});
    $fields->{'volume'} = $ris->{'VL'};
    $fields->{'number'} = $ris->{'IS'} || $ris->{'CP'};
    $fields->{'pages'} = $ris->{'EP'} ?
        "$ris->{'SP'}--$ris->{'EP'}" :
        $ris->{'SP'}; # start page may contain end page
    #CY: city
    $fields->{'publisher'} = $ris->{'PB'};
    $fields->{'issn'} = $1 if
        $ris->{'SN'} && $ris->{'SN'} =~ m[\b(\d{4}-\d{4})\b];
    $fields->{'isbn'} = $ris->{'SN'} if
        $ris->{'SN'} && $ris->{'SN'} =~ m[\b((\d|X)[- ]*){10,13}\b];
    #AD: address
    #AV: (unneeded)
    #M[1-3]: misc
    #U[1-5]: user
    #L1: link to pdf, multiple lines or separated by semi
    #L2: link to text, multiple lines or separated by semi
    #L3: link to records
    #L4: link to images
    $fields->{'doi'} = $ris->{'DO'} || $ris->{'DOI'} || $ris->{'M3'} || (
        $ris->{'N1'} && $ris->{'N1'} =~ $doi && $1);
    #ER

    $fields;
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
    my $content = $mech->content();
    my $i = 1;
    my $cont = undef;
    # Try to avoid SIGPLAN Notices
    while ($mech->find_link(text => 'download', n => $i)) {
        $mech->follow_link(text => 'download', n => $i);
        $cont = $mech->content()
            unless defined $cont and
            $mech->content() =~ m[journal = \{?SIGPLAN Not]i;
        $mech->back();
        $i++;
    }
    $cont =~ s[(\@.*) ][$1]; # Prevent keys with spaces.  E.g. http://portal.acm.org/citation.cfm?id=1411243
    $cont =~ s[<i>(.*?)</i>][{\\it $1}]ig; # HTML -> LaTeX Codes

    my $entry = parse_bibtex($cont);
#    $entry->set($key, $fields{$key}) if defined $fields{$key};

    $mech->back();

    # Un-abbreviated journal title
    # But avoid spurious "journal" when proceedings are published in SIGPLAN Not.
    $entry->set('journal', meta_tag('citation_journal_title'))
        if $entry->exists('journal');

    # Abstract
    my ($abstr_url) = $mech->content() =~ m[(tab_abstract.*?)\'];
    $mech->get($abstr_url);
    $entry->set('abstract', $mech->content() =~
                m[<div style="display:inline">(?:<par>|<p>)?(.+?)(?:</par>|</p>)?</div>]);

    return $entry;

# TODO: uses issue if document is from springer.

# TODO: handle multiple entries

# BUG (ACM's fault): download bibtex link is broken at
#  at http://portal.acm.org/citation.cfm?id=908021&CFID=112731887&CFTOKEN=92268833&preflayout=tabs
}

sub parse_science_direct {
    my ($mech) = @_;

    $mech->follow_link(text => 'Export citation');

    $mech->submit_form(with_fields => {'format' => 'cite',
                                       'citation-type' => 'BIBTEX'});
    my $entry = parse_bibtex($mech->content());
    $mech->back();

    $mech->submit_form(with_fields => {'format' => 'cite-abs', 'citation-type' => 'RIS'});
    my $f = ris_to_bib(parse_ris($mech->content()));
    $entry->set('author', $f->{'author'});
    $entry->set('month', $f->{'month'});
    $entry->set('abstract', $f->{'abstract'});
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
    my $entry = parse_bibtex($mech->content());
    $mech->back();

    $mech->submit_form(
        with_fields => {
            'ctl00$ContentPrimary$ctl00$ctl00$Export' => 'AbstractRadioButton',
# TODO:            'ctl00$ContentPrimary$ctl00$ctl00$Format' => 'RisRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$CitationManagerDropDownList'
                => 'EndNote'},
        button => 'ctl00$ContentPrimary$ctl00$ctl00$ExportCitationButton');
    my $f = ris_to_bib(parse_ris($mech->content()));#decode('utf8', $mech->content())));
    for ('doi', 'month', 'issn', 'isbn') {
        $entry->set($_, $f->{$_}) if $f->{$_};
    }

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
    update($entry, 'abstract', sub {s[\s*ABSTRACT\s+][]});
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

#TODO: find example and fix
sub parse_ieeexplore {
    my ($mech, $fields) = @_;
    my ($record) = $mech->content() =~
        m[<span *id="recordId" *style="display:none;">(\d*)</span>];
#    $mech->get('http://ieeexplore.ieee.org/xpl/downloadCitations?recordIds=1386650&fromPageName=abstract&citations-format=citation-only&download-format=download-bibtex&x=71&y=15');
#    $mech->get('http://ieeexplore.ieee.org/xpl/downloadCitations?recordIds=1386650&fromPageName=abstract&citations-format=citation-only&download-format=download-bibtex&x=71&y=15');
#    $mech->get("http://ieeexplore.ieee.org/xpl/downloadCitations?".
#               "recordIds=1386650&".
#               "recordIds=$record&".
#               "fromPageName=abstract&".
#               "citations-format=citation-only&".
#               "download-format=download-bibtex&x=71&y=15");
    $mech->get("http://ieeexplore.ieee.org/xpl/downloadCitations?".
               "recordIds=$record&".
               "fromPageName=abstract&".
               "citations-format=citation-abstract&".
               "download-format=download-bibtex");
#    print $mech->content(), "\n";

#    $mech->follow_link(
#http://ieeexplore.ieee.org/xpl/downloadCitations?recordIds=1058095&fromPageName=abstract&citations-format=citation-abstract&download-format=download-bibtex&x=37&y=14

#http://ieeexplore.ieee.org/xpl/downloadCitations?recordIds=1058095&fromPageName=abstract&citations-format=citation-abstract&download-format=download-bibtex
    my $cont = $mech->content();
    $cont =~ s/<br>//gi;
    $cont =~ s/month=([^,\.{}"]*?)\./month=$1/;
    return $cont;
}

sub parse_jstor {
    my ($mech) = @_;
    # TODO: abstract is ""?
    $mech->follow_link(text => 'Export Citation');

    # Ick, we have to get around the javascript
    $mech->form_with_fields('suffix');
    my $suffix = $mech->value('suffix');
    $mech->post("http://www.jstor.org/action/downloadSingleCitation",
                {'singleCitation'=>'true', 'suffix'=>$suffix,
                 'include'=>'abs', 'format'=>'bibtex', 'noDoi'=>'yesDoi'});

    my $cont = $mech->content();
    $cont =~ s[\@comment{.*$][]gm; # TODO: get around comments
    $cont =~ s[JSTOR CITATION LIST][]g; # TODO: hack avoid junk chars
    my $entry = parse_bibtex(encode('utf8', $cont));
    $entry->set('doi', $suffix);
    my ($month) = ($entry->get('jstor_formatteddate') =~ m[^(.*)\., \d\d\d\d$]);
    $entry->set('month', $month) if defined $month;
    # TODO: remove empty abstract
    return $entry;
}

sub parse_ios_press {
    my ($mech) = @_;

    $mech->follow_link(text => 'RIS');
    my $f = ris_to_bib(parse_ris($mech->content()));
    my $entry = parse_bibtex("\@$f->{'*type*'} {X,}");
    # TODO: missing items?
    for ('journal', 'title', 'volume', 'number', 'abstract', 'pages',
         'author', 'year', 'month', 'doi') {
        $entry->set($_, encode('utf8', $f->{$_})) if $f->{$_};
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
    $mech->submit_form(with_fields => {'fileFormat' => 'BIBTEX',
                                       'hasAbstract' => 'CITATION_AND_ABSTRACT'});
    my $entry = parse_bibtex($mech->content());
    update($entry, 'abstract', sub { s[^\s*Abstract\s+][] });
    update($entry, 'abstract',
           sub { s[ Copyright .. \d\d\d\d John Wiley \& Sons, Ltd\.$][] });
    return $entry;
}
