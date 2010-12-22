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
    'January' => $months[1],
    $months[2]->[1] => $months[2],
    'February' => $months[2],
    $months[3]->[1] => $months[3],
    'March' => $months[3],
    $months[4]->[1] => $months[4],
    'April' => $months[4],
    $months[5]->[1] => $months[5],
    'May' => $months[5],
    $months[6]->[1] => $months[6],
    'June' => $months[6],
    $months[7]->[1] => $months[7],
    'July' => $months[7],
    $months[8]->[1] => $months[8],
    'August' => $months[8],
    $months[9]->[1] => $months[9],
    'September' => $months[9],
    $months[10]->[1] => $months[10],
    'October' => $months[10],
    $months[11]->[1] => $months[11],
    'November' => $months[11],
    $months[12]->[1] => $months[12],
    'December' => $months[12]);

for my $url (@ARGV) {
    $mech = WWW::Mechanize->new(autocheck => 1);
    #$mech->add_handler("request_send",  sub { shift->dump; return }); # Debug
    #$mech->add_handler("response_done", sub { shift->dump; return }); # Debug
    $mech->agent_alias('Windows IE 6');
    $mech->get($url);

    my %fields;
    my $bib_text = decode('utf8', parse($mech, \%fields));
    $bib_text =~ s/^\x{FEFF}//; # Remove Byte Order Mark

    $entry = new Text::BibTeX::Entry;
    $entry->parse_s ($bib_text, 0); # 1 for preserve values
#    $entry = new Text::BibTeX::Entry($bib_text); # macros: pass "$bib_text, 1"
    die "Can't parse BibTeX" unless $entry->parse_ok;
    for my $key (keys %fields) {
        $entry->set($key, $fields{$key}) if defined $fields{$key};
    }

    # Doi field: remove "http://hostname/" or "DOI: "
    update('doi', sub { s[http://[^/]+/][]i; s[DOI: *][]ig; });
    # Page numbers: no "pp." or "p."
    update('pages', sub { s[pp?\. *][]ig; });
    # Ranges: convert "-" to "--"
    # TODO: might misfire if "-" doesn't represent a range
    #  Common for tech report numbers
    for my $key ('chapter', 'month', 'number', 'pages', 'volume', 'year') {
        update($key, sub { s[ *-+ *][--]ig; });
    }
    # month abbriv: jan, feb, mar, apr, may, jun, jul, aug, sep, oct, nov, dec
    #  ACM: {April}
    # adjust key
    # get PDF
    # abstract:
    # - paragraphs: no marker but often we get ".<Uperchar>" or "<p></p>"
    # - HTML encoding?
    # titles: superscript (r6rs, r5rs), &part;
    # author as editors?

    my $doi = $entry->get('doi');
    $entry->delete('url')
        if $entry->get('url') =~ m[^http://(dx.doi.org|doi.acm.org)/$doi$]
        or $entry->get('url') =~ m[^http://www.sciencedirect.com/science/article];
    $entry->delete('note') if
        $entry->exists('note') and $entry->exists('doi') and
        ($entry->get('note') eq $entry->get('doi') or
         $entry->get('note') eq "");
    if ($entry->exists('issue') and not $entry->exists('number')) {
        $entry->set('number', $entry->get('issue'));
        $entry->delete('issue');
    }

    # \textquotedblleft -> ``
    # \textquoteleft -> `
    # etc.
    # TODO: detect fields that are already unicoded (e.g. {H}askell or $p$)
    # Eliminate Unicode
    for my $field ($entry->fieldlist()) {
        $entry->set($field, latex_encode(decode('utf8', $entry->get($field))))
            # But not for doi and url fields (assuming \usepackage{url})
            unless $field eq 'doi' or $field eq 'url'
    }

    update('month', # Must be after field encoding
           sub { $_ = new Text::BibTeX::Value(
                     map { $months{$_} or [Text::BibTeX::BTAST_STRING, $_] }
                     split qr[\b]) });

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
    my ($field, $fun) = @_;
    if ($entry->exists($field)) {
        $_ = $entry->get($field);
        &$fun();
        $entry->set($field, $_);
    }
}

sub meta_tag {
    my ($name) = @_;
    my $p = new HTML::HeadParser;
    $p->parse($mech->content());
    return $p->header('X-Meta-' . $name);
}

sub ris_fields {
    return map { my ($x) = m[\Q$_[0]\E *- *([^\r\n]*)]; $x; }
           grep(m[^\Q$_[0]\E *-], split("\n", $_[1]));
}

sub ris_name { s[(.*),(.*),(.*)][$1,$3,$2]; $_; }

sub ris_month {
    my ($year, $month) = (split m[/|-], $_[0]);
    $month and $months[$month]->[1];
}

################

sub parse {
    my ($mech, $fields) = @_;

### ACM
    if (domain('acm.org')) {

        # Un-abbreviated journal title
        $fields->{'journal'} = meta_tag('citation_journal_title');

        # Abstract
        my ($abstr_url) = $mech->content() =~ m[(tab_abstract.*?)\'];
        $mech->get($abstr_url);
        ($fields->{'abstract'}) = $mech->content() =~
            m[<div style="display:inline">(?:<par>|<p>)?(.+?)(?:</par>|</p>)?</div>];
        $mech->back();

        # BibTeX
        my ($url) = $mech->find_link(text=>'BibTeX')->url()
            =~ m[navigate\('(.*?)'];
        $mech->get($url);
        $mech->follow_link(text => 'download');
        return $mech->content();

# TODO: uses issue if document is from springer.

# TODO: handle multiple entries

# BUG (ACM's fault): download bibtex link is broken at
#  at http://portal.acm.org/citation.cfm?id=908021&CFID=112731887&CFTOKEN=92268833&preflayout=tabs

### ScienceDirect
    } elsif (domain('sciencedirect.com')) {
        $mech->follow_link(class => 'icon_exportarticlesci_dir');
        $mech->submit_form(with_fields => {'citation-type' => 'RIS'});
        $fields->{'author'} =
            join(" and ", map(ris_name, ris_fields('AU', $mech->content())));
# TODO: editor
# TODO: blank note?!
        $mech->back();
        $mech->submit_form(with_fields => {'format' => 'cite-abs',
                                           'citation-type' => 'BIBTEX'});
        return $mech->content();

### SpringerLink
    } elsif (domain('springerlink.com')) {

# TODO: remove 'note'
# TODO: handle books
# TODO: uses 'issue' but should use 'number'?

        $mech->follow_link(url_regex => qr[/export-citation/])
            unless $mech->uri() =~ m[/export-citation/];
        $mech->submit_form(
          with_fields => {
            'ctl00$ContentPrimary$ctl00$ctl00$Export' => 'AbstractRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$Format' => 'RisRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$CitationManagerDropDownList'
                => 'EndNote'},
            button => 'ctl00$ContentPrimary$ctl00$ctl00$ExportCitationButton');
        ($fields->{'doi'}) = ris_fields('DO', $mech->content());
        my ($date) = (ris_fields('PY', $mech->content()),
                      ris_fields('Y1', $mech->content()));
        $fields->{'month'} = ris_month($date);
        my ($sn) = ris_fields('SN', $mech->content());
        $fields->{'issn'} = $sn if $sn =~ m[\b\d{4}-\d{4}\b];
        $fields->{'isbn'} = $sn if $sn =~ m[\b((\d|X)[- ]*){10,13}\b];
        $mech->back();

        $mech->submit_form(
          with_fields => {
            'ctl00$ContentPrimary$ctl00$ctl00$Export' => 'AbstractRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$Format' => 'RisRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$CitationManagerDropDownList'
                => 'BibTex'},
            button => 'ctl00$ContentPrimary$ctl00$ctl00$ExportCitationButton');
        return $mech->content();

### Cambridge University Press
    } elsif (domain('journals.cambridge.org')) {
        $mech->follow_link(text => 'Export Citation');
        $mech->submit_form(form_name => 'exportCitationForm',
                           fields => {'Download' => 'Download',
                                      'displayAbstract' => 'Yes',
                                      'format' => 'BibTex'});
        return $mech->content();
        # TODO: fix authors and abstract

### IEEE Computer Society
    } elsif (domain('computer.org')) {
        $mech->follow_link(text => 'BibTex');
        return $mech->content();
        # TODO: volume is 0?

### JStor
    } elsif (domain('jstor.org')) {
        # TODO: abstract is ""?
        $mech->follow_link(text => 'Export Citation');
        $mech->form_with_fields('suffix');
        my $suffix = $mech->value('suffix');
        $fields->{'doi'} = $suffix;
        $mech->post('http://www.jstor.org/action/downloadSingleCitation?' .
                    'format=bibtex&include=abs&singleCitation=true',
                    {'suffix' => $suffix});
        my $text = $mech->content();
        $text =~ s[\@comment{.*$][]gm; # TODO: A bit of a hack
        return $text;

    } else {
        die "Unknown URI: " . $mech->uri();
    }
}
