#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use WWW::Mechanize;
use Text::BibTeX;
use HTML::HeadParser;

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

    $entry = new Text::BibTeX::Entry($bib_text);
    die "error in input" unless $entry->parse_ok;
    $entry->set(%fields);

    # Doi field: remove "http://hostname/" or "DOI: "
    update('doi', sub { s[http://[^/]+/][]i; s[DOI: *][]i; });
    # Page numbers: "-" -> "--" and no "pp." or "p."
    update('pages', sub { s[(\d+) *- *(\d+)][$1--$2]; });
    update('pages', sub { s[pp?\. *][]; });
    # Number: "-" -> "--"
    # abstract
    # de-unicode
    # adjust key
    # normalize authors?

    print $entry->print_s();
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

################

sub parse {
    my ($mech, $fields) = @_;

### ACM
    if (domain('acm.org')) {

        # Fix abbriviations in journal field
        my ($journal) = meta('citation_journal_title');
        $fields->{'journal'} = $journal if $journal;

        # Get the abstract
        my ($abstr_url) = $mech->content() =~ m[(tab_abstract.*?)\'];
#        my ($pid, $id) = meta('citation_abstract_html_url')
#          =~ m[http://portal\.acm\.org/citation\.cfm\?id=(\d+)\.(\d+)];
#        $mech->get("http://portal.acm.org/tab_abstract.cfm" .
#                   "?id=$id&usebody=tabbody");
        $mech->get($abstr_url);
        my ($abstract) = $mech->content() =~
            m[<div style="display:inline">(?:<par>)?(.+?)(?:</par>)?</div>];
        # TODO: Paragraphs? There is no marker but often we get ".<Uperchar>".
        #   But sometimes we get <p></p>
        #  TODO: HTML encoding?
        $fields->{'abstract'} = $abstract if $abstract;
        $mech->back();

        my ($url) = $mech->find_link(text=>'BibTeX')->url()
            =~ m[navigate\('(.*?)'];
        $mech->get($url);
        $mech->follow_link(text => 'download');
        return $mech->content();

# TODO: get PDF
# TODO: handle multiple entries

# BUG (ACM's fault): download bibtex link is broken at
#  at http://portal.acm.org/citation.cfm?id=908021&CFID=112731887&CFTOKEN=92268833&preflayout=tabs

### ScienceDirect
    } elsif (domain('sciencedirect.com')) {
        $mech->follow_link(class => 'icon_exportarticlesci_dir');
        $mech->submit_form(with_fields => {'citation-type' => 'RIS'});
        my ($author) = join(" and ",
                            map {my ($x) = /^AU *- *([^\r\n]*)/; $x;}
                            grep(/^AU/, split("\n", $mech->content())));
        $fields->{'author'} = $author;
        $mech->back();
        $mech->submit_form(with_fields => {'citation-type' => 'BIBTEX'});
        return $mech->content();

### SpringerLink
    } elsif (domain('springerlink.com')) {
        $mech->follow_link(url_regex => qr/export-citation/);
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
