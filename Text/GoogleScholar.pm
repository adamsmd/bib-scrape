package Text::GoogleScholar;

use HTML::HeadParser;
use Text::BibTeX;
use Text::BibTeX::Months;

# See http://www.refman.com/support/risformat_intro.asp for format

use Class::Struct 'Text::GoogleScholar' => { data => '%' };

sub Text::GoogleScholar::get    { my ($self, $key) = @_;       $self->data->{$key} }
sub Text::GoogleScholar::set    { my ($self, $key, $val) = @_; $self->data->{$key} = $val }
sub Text::GoogleScholar::exists { my ($self, $key) = @_;       exists $self->data->{$key} }
sub Text::GoogleScholar::delete { my ($self, $key) = @_;       delete $self->data->{$key} }

sub meta_tag {
    my ($name) = @_;
    my $p = new HTML::HeadParser;
    $p->parse($mech->content());
    return $p->header('X-Meta-' . $name);
}

sub Text::GoogleScholar::parse {
    my ($text) = @_;

    my $data = {};

    my $p = new HTML::HeadParser;
    $p->parse($text);
    $p->header()->scan(sub {
        my ($key, $value) = @_;
        if ($key =~ m[^X-Meta-(citation-.*)$]i) {
            ($key = lc $1) =~ s/-/_/g;
            push @{$data->{lc $key}}, $value;
        }});

    return Text::GoogleScholar->new(data => $data);
}

sub Text::GoogleScholar::bibtex {
    my ($self) = @_;
    $self = {%{$self->data}};

    my $entry = new Text::BibTeX::Entry;
    $entry->parse_s("\@misc{HTML-META,}", 0); # 1 for preserve values

    my $authors = $self->{'citation_authors'}->[0] ||
        join(" ; ", @{$self->{'citation_author'} || []});
    $authors =~ s[;][ and ]g;
    $authors =~ s[  +][ ]g;
    $entry->set('author', $authors);

    $entry->set('keywords', join " ; ", @{$self->{'citation_keywords'}})
        if $self->{'citation_keywords'};
    $entry->set('abstract_html_url', join " ; ", @{$self->{'citation_abstract_html_url'}})
        if $self->{'citation_abstract_html_url'};
    $entry->set('fulltext_html_url', join " ; ", @{$self->{'citation_fulltext_html_url'}})
        if $self->{'citation_fulltext_html_url'};
    $entry->set('pdf_url', join " ; ", @{$self->{'citation_pdf_url'}})
        if $self->{'citation_pdf_url'};

    for (keys %$self) { $self->{$_} = join " ; ", @{$self->{$_}} }

    $entry->set('title', $self->{'citation_title'});
    $entry->set('booktitle',
                $self->{'citation_conference'} || $self->{'citation_conference_title'});
    $entry->set('journal', $self->{'citation_journal_title'});
    $entry->set('volume', $self->{'citation_volume'});
    $entry->set('number', ($self->{'citation_issue'} ||
                           $self->{'citation_patent_number'} ||
                           $self->{'citation_technical_report_number'}));
    $entry->set('nationality', $self->{'citation_patent_country'});

    $entry->set('pages', "$self->{'citation_firstpage'}--$self->{'citation_lastpage'}");

    my ($year, $month, $day) = split m[/|-], $self->{'citation_date'};
    $entry->set('year', $year);
    $entry->set('month', num2month($month)->[1]) if $month;
    $entry->set('day', $day);

    $entry->set($_, $self->{"citation_$_"}) for (qw(
        online_date publisher language isbn issn doi pmid));

    $entry->set('institution', ($self->{'citation_dissertation_institution'} ||
                                $self->{'citation_technical_report_institution'}));
    #citation_dissertation_name

    $entry->set_type(
        exists $self->{'citation_journal_title'} ? 'article' :
        exists $self->{'citation_conference'} ? 'inproceedings' :
        exists $self->{'citation_conference_title'} ? 'inproceedings' :
        exists $self->{'citation_dissertation_institution'} ? undef : # phd vs masters
        exists $self->{'citation_technical_report_institution'} ? 'techreport' :
        exists $self->{'citation_technical_report_number'} ? 'techreport' :
        exists $self->{'citation_patent_number'} ? 'patent' :
        warn "Unknown type. Using misc" and 'misc');

    #warn unknown field type

    for ($entry->fieldlist) { $entry->delete($_) if not defined $entry->get($_) }

    return $entry;
}

1;

#dc.Contributor
#DC.Contributor
#dc.Date
#DC.Date
#DC.Identifier
#DC.Publisher
#dc.Title
#DC.Title
