#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use WWW::Mechanize;
use Text::BibTeX;
use HTML::HeadParser;

my $url = $ARGV[0];

my $bib_text;
my %fields;
my $mech = WWW::Mechanize->new(autocheck => 1);
#$mech->add_handler("request_send",  sub { shift->dump; return }); # Debug
#$mech->add_handler("response_done", sub { shift->dump; return }); # Debug
$mech->agent_alias( 'Windows IE 6' );
# quiet => 1

$mech->get($url);

sub domain { $mech->uri()->authority() =~ m[^(|.*\.)\Q$_[0]\E]i; }
sub meta {
    my ($name) = @_;
    my $p = new HTML::HeadParser;
    $p->parse($mech->content());
    return $p->header('X-Meta-' . $name);
}

if (domain('acm.org')) {
    # Fix abbriviations in journal field
    my ($journal) = meta('citation_journal_title');
    $fields{'journal'} = $journal if $journal;
    # TODO: abstract

    my ($url) = $mech->find_link(text=>'BibTeX')->url() =~ m[navigate\('(.*?)'];
    $mech->get($url);
    $mech->follow_link(text => 'download');
    $bib_text = $mech->content;

} elsif (domain('sciencedirect.com')) {
    $mech->follow_link(class => 'icon_exportarticlesci_dir');
    $mech->submit_form(with_fields => {'citation-type' => 'BIBTEX'});
    $bib_text = $mech->content();
    $mech->back();
    $mech->submit_form(with_fields => {'citation-type' => 'RIS'}); # RIS for authors
    print $mech->content();

} elsif (domain('springerlink.com')) {
    $mech->follow_link(url_regex => qr/export-citation/);
    $mech->submit_form(
        with_fields => {
            'ctl00$ContentPrimary$ctl00$ctl00$Export' => 'AbstractRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$Format' => 'RisRadioButton',
            'ctl00$ContentPrimary$ctl00$ctl00$CitationManagerDropDownList' =>
                'BibTex'},
        button => 'ctl00$ContentPrimary$ctl00$ctl00$ExportCitationButton');
    $bib_text = $mech->content();

} elsif (domain('journals.cambridge.org')) {
    $mech->follow_link(text => 'Export Citation');
    $mech->submit_form(form_name => 'exportCitationForm',
                       fields => {'Download' => 'Download',
                                  'displayAbstract' => 'Yes',
                                  'format' => 'BibTex'});
    $bib_text = $mech->content();
    # TODO: fix authors and abstract

} elsif (domain('computer.org')) {
    $mech->follow_link(text => 'BibTex');
    $bib_text = $mech->content();

} elsif (domain('jstor.org')) {
    $mech->follow_link(text => 'Export Citation');
    $mech->form_with_fields('suffix');
    my $suffix = $mech->value('suffix');
    $fields{'doi'} = $suffix;
    $mech->post('http://www.jstor.org/action/downloadSingleCitation?' .
                'format=bibtex&include=abs&singleCitation=true',
                {'suffix' => $suffix});
    $bib_text = $mech->content();
    $bib_text =~ s[\@comment{.*$][]gm; # TODO: A bit of a hack
    # TODO: abstract

} else {
    die "Unknown URI: " . $mech->uri();
}

################
# Generate BibTeX
################
my $entry = new Text::BibTeX::Entry($bib_text);

die "error in input" unless $entry->parse_ok;

sub modify {
    my ($field, $fun) = @_;
    if ($entry->exists($field)) {
        $_ = $entry->get($field);
        &$fun();
        $entry->set($field, $_);
    }
}

# Doi field: remove "http://hostname/" or "DOI: "
modify('doi', sub { s[http://[^/]+/][]i; s[DOI: *][]i; });
# Page numbers: "-" -> "--" and no "pp." or "p."
modify('pages', sub { s[(\d+) *- *(\d+)][$1--$2]; });
modify('pages', sub { s[pp?\. *][]; });
# Number: "-" -> "--"

$entry->set(%fields);

# abstract
# de-unicode
# adjust key
# normalize authors?

print $entry->print_s(), "\n";
