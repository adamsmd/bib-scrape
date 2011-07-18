package Text::RIS;

use Text::BibTeX;
use Text::BibTeX::Months;

# See http://www.refman.com/support/risformat_intro.asp for format

use Class::Struct 'Text::RIS' => { data => '%' };

sub Text::RIS::get { my ($self, $key) = @_; $self->data->{$key} }
sub Text::RIS::set { my ($self, $key, $val) = @_; $self->data->{$key} = $val }
sub Text::RIS::exists { my ($self, $key) = @_; exists $self->data->{$key} }

sub Text::RIS::parse {
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
    Text::RIS->new(data => $ris);
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

sub ris_author { join(" and ", map { s[(.*),(.*),(.*)][$1,$3,$2];
                                     m[[^, ]] ? $_ : (); } @_); }

sub Text::RIS::bibtex {
    my ($ris) = @_;
    $ris = {%{$ris->data}};

    my $entry = new Text::BibTeX::Entry;
    $entry->parse_s("\@misc{RIS,}", 0); # 1 for preserve values

    $entry->set('author', ris_author(@{$ris->{'A1'} || $ris->{'AU'} || []}));
    $entry->set('editor', ris_author(@{$ris->{'A2'} || $ris->{'ED'} || []}));
    $entry->set('keywords', join " ; ", @{$ris->{'KW'}}) if $ris->{'KW'};
    $entry->set('url', join " ; ", @{$ris->{'UR'}}) if $ris->{'UR'};

    for (keys %$ris) { $ris->{$_} = join "", @{$ris->{$_}} }

    my $doi = qr[^(\s*doi:\s*\w+\s+)?(.*)$]s;

    # TODO: flattening
    $entry->set_type(exists $ris_types{$ris->{'TY'}} ?
        $ris_types{$ris->{'TY'}} :
        (print STDERR "Unknown RIS TY: $ris->{'TY'}. Using misc.\n" and 'misc'));
    #ID: ref id
    $entry->set('title', $ris->{'T1'} || $ris->{'TI'} || $ris->{'CT'} || (
        ($ris->{'TY'} eq 'BOOK' || $ris->{'TY'} eq 'UNPB') && $ris->{'BT'}));
    $entry->set('booktitle', $ris->{'T2'} || (
        !($ris->{'TY'} eq 'BOOK' || $ris->{'TY'} eq 'UNPB') && $ris->{'BT'}));
    $entry->set('series', $ris->{'T3'}); # check
    #A3: author series
    #A[4-9]: author (undocumented)
    my ($year, $month, $day) = split m[/|-], ($ris->{'PY'} || $ris->{'Y1'});
    $entry->set('year', $year);
    $entry->set('month', num2month($month)->[1]) if $month;
    $entry->set('day', $day);
    #Y2: date secondary
    ($ris->{'N1'} || $ris->{'AB'} || $ris->{'N2'} || "") =~ $doi;
    $entry->set('abstract', $2) if length($2);
    #RP: reprint status (too complex for what we need)
    $entry->set('journal', ($ris->{'JF'} || $ris->{'JO'} || $ris->{'JA'} ||
                            $ris->{'J1'} || $ris->{'J2'}));
    $entry->set('volume', $ris->{'VL'});
    $entry->set('number', $ris->{'IS'} || $ris->{'CP'});
    $entry->set('pages', $ris->{'EP'} ?
        "$ris->{'SP'}--$ris->{'EP'}" :
        $ris->{'SP'}); # start page may contain end page
    #CY: city
    $entry->set('publisher', $ris->{'PB'});
    $entry->set('issn', $1) if
        $ris->{'SN'} && $ris->{'SN'} =~ m[\b(\d{4}-\d{4})\b];
    $entry->set('isbn', $ris->{'SN'}) if
        $ris->{'SN'} && $ris->{'SN'} =~ m[\b((\d|X)[- ]*){10,13}\b];
    #AD: address
    #AV: (unneeded)
    #M[1-3]: misc
    #U[1-5]: user
    #L1: link to pdf, multiple lines or separated by semi
    #L2: link to text, multiple lines or separated by semi
    #L3: link to records
    #L4: link to images
    $entry->set('doi', $ris->{'DO'} || $ris->{'DOI'} || $ris->{'M3'} || (
        $ris->{'N1'} && $ris->{'N1'} =~ $doi && $1));
    #ER

    for ($entry->fieldlist) { $entry->delete($_) if not defined $entry->get($_) }

    $entry;
}

1;

__END__

sub Text::RIS::parse {
    my ($text) = @_;
    my $ris = {}; #  {key, [string]}
    my $last_key = "";
    for my $line (map { tr[\r\n][] } split("\n", $text)) {
        ($key, $val) = m[^([A-Z][A-Z0-9]|DOI)  - *(.*?) *$];
        push @{$ris->{$key}}, $val if defined $key;
    } elsif ("" ne $line) {
            $list = $ris->{$last_key};
            @$list[$#$list] .= "\n" . $line;
    } else {} # blank line
Text::RIS::new($ris);
}

            if ("ER" eq $key) {
                if (exists $ris->{'SP'}) {
                    my ($sp, $ep) = $ris->{'SP'}[0] =~
                        m[^ *(\d+) *-+ *(\d+) *$];
                    $ris->{'EP'}[0] = $ep if (defined $ep);
                }
                push @ris $ris; $ris = {};
            }
}

1;

__END__

# last, first, suffix -> von Last, Jr, First
# (skip [,\.]*)
sub ris_name { $_[0] =~ s[(.*),(.*),(.*)][$1,$3,$2];  $_[0]; }
sub ris_date { split m[/|-]; (other field may be empty)} # 4 fields
sub ris_pages { (\d+)-(\d+) }


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
