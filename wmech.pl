#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use WWW::Mechanize;
use Text::BibTeX;
use HTML::HeadParser;
use TeX::Encode;
use Encode;

#print %TeX::Encode::LATEX_Escapes;

my $mech;
my $entry;

for my $url (@ARGV) {
    $mech = WWW::Mechanize->new(autocheck => 1);
    #$mech->add_handler("request_send",  sub { shift->dump; return }); # Debug
    #$mech->add_handler("response_done", sub { shift->dump; return }); # Debug
    $mech->agent_alias( 'Windows IE 6' );
    $mech->get($url);

    my %fields;
    my $bib_text = parse($mech, \%fields);

#    $entry = new Text::BibTeX::Entry(latex_encode(decode('utf8', $bib_text)));
    $entry = new Text::BibTeX::Entry($bib_text);
    die "Can't parse BibTeX" unless $entry->parse_ok;
    for my $key (keys %fields) {
        $entry->set($key, $fields{$key}) if defined $fields{$key};
    }

    # Doi field: remove "http://hostname/" or "DOI: "
    update('doi', sub { s[http://[^/]+/][]i; s[DOI: *][]i; });
    # Page numbers: "-" -> "--" and no "pp." or "p."
    update('pages', sub { s[(\d+) *- *(\d+)][$1--$2]; });
    update('pages', sub { s[pp?\. *][]; });
    # Number/issue/etc.: "-" -> "--"
    # adjust key
    # get PDF
    # abstract
        # TODO: Paragraphs? There is no marker but often we get ".<Uperchar>".
        #   But sometimes we get <p></p>
        #  TODO: HTML encoding?

    # Eliminate Unicode
    for my $field ($entry->fieldlist()) {
        $entry->set($field, latex_encode(decode('utf8', $entry->get($field))));
    }

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

sub meta {
    my ($name) = @_;
    my $p = new HTML::HeadParser;
    $p->parse($mech->content());
    return $p->header('X-Meta-' . $name);
}

sub ris_fields {
    return
        map { my ($x) = m[\Q$_[0]\E *- *([^\r\n]*)]; $x; }
        grep(m[^\Q$_[0]\E *-], split("\n", $_[1]));
}

sub ris_name { s[(.*),(.*),(.*)][$1,$3,$2]; $_; }

################

sub parse {
    my ($mech, $fields) = @_;

### ACM
    if (domain('acm.org')) {

        # Un-abbreviated journal title
        $fields->{'journal'} = meta('citation_journal_title');

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

# TODO: handle multiple entries

# BUG (ACM's fault): download bibtex link is broken at
#  at http://portal.acm.org/citation.cfm?id=908021&CFID=112731887&CFTOKEN=92268833&preflayout=tabs

### ScienceDirect
    } elsif (domain('sciencedirect.com')) {
        $mech->follow_link(class => 'icon_exportarticlesci_dir');
        $mech->submit_form(with_fields => {'citation-type' => 'RIS'});
        $fields->{'author'} =
            join(" and ", map(ris_name, ris_fields('AU', $mech->content())));
        $mech->back();
        $mech->submit_form(with_fields => {'citation-type' => 'BIBTEX'});
        return $mech->content();

### SpringerLink
    } elsif (domain('springerlink.com')) {

# TODO: remove 'note'
# TODO: handle books

        $mech->follow_link(url_regex => qr/export-citation/);
        $mech->submit_form(
          with_fields => {
            'ctl00$ContentPrimary$ctl00$ctl00$Export' => 'AbstractRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$Format' => 'RisRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$CitationManagerDropDownList' => 'EndNote'},
            button => 'ctl00$ContentPrimary$ctl00$ctl00$ExportCitationButton');
        ($fields->{'doi'}) = ris_fields('DO', $mech->content());
        my ($sn) = ris_fields('SN', $mech->content());
        $fields->{'issn'} = $sn if $sn =~ /\b\d{4}-\d{4}\b/;
        $fields->{'isbn'} = $sn if $sn =~ /\b((\d|X)[- ]*){10,13}\b/;
        $mech->back();

        $mech->submit_form(
          with_fields => {
            'ctl00$ContentPrimary$ctl00$ctl00$Export' => 'AbstractRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$Format' => 'RisRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$CitationManagerDropDownList' => 'BibTex'},
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

### JStor
    } elsif (domain('jstor.org')) {
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
        # TODO: abstract

    } else {
        die "Unknown URI: " . $mech->uri();
    }
}
