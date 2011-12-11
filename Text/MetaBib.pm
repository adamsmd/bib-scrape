package Text::MetaBib;

use strict;
use warnings;

use HTML::HeadParser;
#use Text::BibTeX;
use Text::BibTeX::Months;

use Class::Struct 'Text::MetaBib' => { data => '%' };

sub Text::MetaBib::get    { my ($self, $key) = @_;       $self->data->{$key} }
sub Text::MetaBib::set    { my ($self, $key, $val) = @_; $self->data->{$key} = $val }
sub Text::MetaBib::exists { my ($self, $key) = @_;       exists $self->data->{$key} }
sub Text::MetaBib::delete { my ($self, $key) = @_;       delete $self->data->{$key} }

sub Text::MetaBib::parse {
    my ($text) = @_;
    my $data = {};

    my $p = new HTML::Parser;
    $p->report_tags('meta');
    $p->handler(start => sub {
        my %a = %{$_[0]};
        push @{$data->{lc $a{'name'}}}, $a{'content'} if $a{'name'}; }, 'attr');
    $p->parse($text);

    return Text::MetaBib->new(data => $data);
}

sub Text::MetaBib::authors {
    my ($self) = @_;
    my @authors;
    push @authors, split(';', ($self->data->{'citation_authors'}->[0] || ''));
    push @authors, @{$self->data->{'citation_author'} || []};
    push @authors, split(',', $self->data->{'dc.creator'}->[0] || "");
    return join(' and ', map { s[^ +][]g; s[ +$][]g; $_ } @authors);
}

sub Text::MetaBib::type {
    my ($self) = @_;
    my %data = %{$self->data};

    if (exists $data{'citation_journal_title'}) { return 'article'; }
    if (exists $data{'citation_conference'}) { return 'inproceedings'; }
    if (exists $data{'citation_conference_title'}) { return 'inproceedings'; }
    if (exists $data{'citation_dissertation_institution'}) { return undef; } # phd vs masters
    if (exists $data{'citation_technical_report_institution'}) { return 'techreport'; }
    if (exists $data{'citation_technical_report_number'}) { return 'techreport'; }
    if (exists $data{'citation_patent_number'}) { return 'patent'; }
    return undef;
}

sub Text::MetaBib::date {
    my ($self, $field) = @_;
    my ($year, $month, $day) = ($self->data->{$field}->[0] =~ m[(\d{4})[/-](\d{2})[/-](\d{2})]);
    return ($year, num2month($month)->[1], $day);
}

sub Text::MetaBib::pages {
    my ($self) = @_;
    return undef unless exists $self->data->{'citation_firstpage'};
    my $pages = $self->data->{'citation_firstpage'}->[0];
    $pages .= "--" . $self->data->{'citation_lastpage'}->[0] if
        exists $self->data->{'citation_lastpage'};
    return $pages;
}

1;

=cut

sub keywords {
    $entry->set('keywords', join " ; ", @{$self->{'citation_keywords'}})
        if $self->{'citation_keywords'};
    $entry->set('fulltext_html_url', join " ; ", @{$self->{'citation_fulltext_html_url'}})
        if $self->{'citation_fulltext_html_url'};
    $entry->set('pdf_url', join " ; ", @{$self->{'citation_pdf_url'}})
        if $self->{'citation_pdf_url'};
}

    for (keys %$self) { $self->{$_} = join " ; ", @{$self->{$_}} }

    $entry->set('volume', $self->{'citation_volume'});
    $entry->set('abstract', @{$self->{'dc.description'}}) if exists $self->{'dc.description'};
    $entry->set('nationality', $self->{'citation_patent_country'});
    $entry->set($_, $self->{"citation_$_"}) for (qw(
        online_date publisher language isbn issn doi pmid));

title:
    $entry->set('title', $self->{'citation_title'} || $self->{'dc.title'});

booktitle:
    $entry->set('booktitle',
                $self->{'citation_conference'} || $self->{'citation_conference_title'} ||
                $self->{'dc.relation.ispartof'});

journal:
    $entry->set('journal',
                $self->{'citation_journal_title'} ||
                $self->{'dc.relation.ispartof'});

number:
    $entry->set('number', ($self->{'citation_issue'} ||
                           $self->{'citation_patent_number'} ||
                           $self->{'citation_technical_report_number'}));

pages:
    $entry->set('pages', "$self->{'citation_firstpage'}--$self->{'citation_lastpage'}");

institution:
    $entry->set('institution', ($self->{'citation_dissertation_institution'} ||
                                $self->{'citation_technical_report_institution'}));
