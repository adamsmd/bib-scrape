package Text::RIS;

use Text::BibTeX;
use Text::BibTeX::Months;

# See http://www.refman.com/support/risformat_intro.asp for format

use Class::Struct 'Text::RIS' => { data => '%' };

sub Text::RIS::get    { my ($self, $key) = @_;       $self->data->{$key} }
sub Text::RIS::set    { my ($self, $key, $val) = @_; $self->data->{$key} = $val }
sub Text::RIS::exists { my ($self, $key) = @_;       exists $self->data->{$key} }
sub Text::RIS::delete { my ($self, $key) = @_;       delete $self->data->{$key} }

sub Text::RIS::parse {
    my ($text) = @_;
    $text =~ s/^\x{FEFF}//; # Remove Byte Order Mark

    my $data = {}; # {key, [string]}
    my $last_key = "";
    for my $line (split("\n", $text)) { #(split("\n", $text))) {
        $line =~ s[\r|\n][]g;
        my ($key, $val) = $line =~ m[^([A-Z][A-Z0-9]|DOI)  - *(.*?) *$];
        if (defined $key) { push @{$data->{$key}}, $val; $last_key = $key; }
        elsif ("" ne $line) {
            my $list = $data->{$last_key};
            @$list[$#$list] .= "\n" . $line;
        } else {} # blank line
    }

    return Text::DATA->new(data => $data);
}

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

# last, first, suffix -> von Last, Jr, First
# (skip [,\.]*)
sub ris_author { join(" and ", map { s[(.*),(.*),(.*)][$1,$3,$2];
                                     m[[^, ]] ? $_ : (); } @_); }

sub Text::RIS::bibtex {
    my ($self) = @_;
    $self = {%{$self->data}};

    my $entry = new Text::BibTeX::Entry;
    $entry->parse_s("\@misc{RIS,}", 0); # 1 for preserve values

    $entry->set('author', ris_author(@{$self->{'A1'} || $self->{'AU'} || []}));
    $entry->set('editor', ris_author(@{$self->{'A2'} || $self->{'ED'} || []}));
    $entry->set('keywords', join " ; ", @{$self->{'KW'}}) if $self->{'KW'};
    $entry->set('url', join " ; ", @{$self->{'UR'}}) if $self->{'UR'};

    for (keys %$self) { $self->{$_} = join " ; ", @{$self->{$_}} }

    my $doi = qr[^(\s*doi:\s*\w+\s+)?(.*)$]s;

    # TODO: flattening
    $entry->set_type(exists $self_types{$self->{'TY'}} ?
        $self_types{$self->{'TY'}} :
        (print STDERR "Unknown RIS TY: $self->{'TY'}. Using misc.\n" and 'misc'));
    #ID: ref id
    $entry->set('title', $self->{'T1'} || $self->{'TI'} || $self->{'CT'} || (
        ($self->{'TY'} eq 'BOOK' || $self->{'TY'} eq 'UNPB') && $self->{'BT'}));
    $entry->set('booktitle', $self->{'T2'} || (
        !($self->{'TY'} eq 'BOOK' || $self->{'TY'} eq 'UNPB') && $self->{'BT'}));
    $entry->set('series', $self->{'T3'}); # check
    #A3: author series
    #A[4-9]: author (undocumented)
    my ($year, $month, $day) = split m[/|-], ($self->{'PY'} || $self->{'Y1'});
    $entry->set('year', $year);
    $entry->set('month', num2month($month)->[1]) if $month;
    $entry->set('day', $day);
    #Y2: date secondary
    ($self->{'N1'} || $self->{'AB'} || $self->{'N2'} || "") =~ $doi;
    $entry->set('abstract', $2) if length($2);
    #RP: reprint status (too complex for what we need)
    $entry->set('journal', ($self->{'JF'} || $self->{'JO'} || $self->{'JA'} ||
                            $self->{'J1'} || $self->{'J2'}));
    $entry->set('volume', $self->{'VL'});
    $entry->set('number', $self->{'IS'} || $self->{'CP'});
    $entry->set('pages', $self->{'EP'} ?
        "$self->{'SP'}--$self->{'EP'}" :
        $self->{'SP'}); # start page may contain end page
    #CY: city
    $entry->set('publisher', $self->{'PB'});
    $entry->set('issn', $1) if
        $self->{'SN'} && $self->{'SN'} =~ m[\b(\d{4}-\d{4})\b];
    $entry->set('isbn', $self->{'SN'}) if
        $self->{'SN'} && $self->{'SN'} =~ m[\b((\d|X)[- ]*){10,13}\b];
    #AD: address
    #AV: (unneeded)
    #M[1-3]: misc
    #U[1-5]: user
    #L1: link to pdf, multiple lines or separated by semi
    #L2: link to text, multiple lines or separated by semi
    #L3: link to records
    #L4: link to images
    $entry->set('doi', $self->{'DO'} || $self->{'DOI'} || $self->{'M3'} || (
        $self->{'N1'} && $self->{'N1'} =~ $doi && $1));
    #ER

    for ($entry->fieldlist) { $entry->delete($_) if not defined $entry->get($_) }

    return $entry;
}

1;

__END__

TY: ref type (INCOL|CHAPTER -> CHAP, REP -> RPRT)
ID: ref id
T1|TI|CT: title primary
T2: title secondary
BT: title primary (books and unpub), title secondary (otherwise)
T3: title series
A1|AU: author primary
A2|ED: author secondary
A3: author series
A[4-9]: author (undocumented)
Y1|PY: date primary
Y2: date secondary
N1|AB: notes (skip leading doi)
N2: abstract (skip leading doi)
KW: keyword. multiple
RP: reprint status (too complex for what we need)
JF|JO: periodical name, full
JA: periodical name, abbriviated
J1: periodical name, user abbriv 1
J2: periodical name, user abbriv 2
VL: volume number
IS|CP: issue
SP: start page (may contain end page)
EP: end page
CY: city
PB: publisher
SN: isbn or issn
AD: address
AV: (unneeded)
M[1-3]: misc
U[1-5]: user
UR: multiple lines or separated by semi, may try for doi
L1: link to pdf, multiple lines or separated by semi
L2: link to text, multiple lines or separated by semi
L3: link to records
L4: link to images
DO|DOI: doi
ER

IS
CP|CY
