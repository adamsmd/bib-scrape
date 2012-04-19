#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use Getopt::Long qw(:config auto_version auto_help);

use Text::BibTeX::Fix;
use Text::BibTeX::Name;
use Text::BibTeX::Scrape;

$main::VERSION='1.1';

=head1 SYNOPSIS

bib-scrape.pl [options] <url> ...

=head2 URL

Formats are usually 'http://...', but 'doi:...' is also allowed.

=head2 OPTIONS

=item --bibtex

=item --no-bibtex

Take input as BibTeX data from standard input in addition to the
default of taking input as URLs from the command line.
[default=no]

=item --debug

=item --no-debug

Print debug data (TODO: make it verbose and go to STDERR)
[default=no]

=item --omit=field

Omit a particular field from the output.

=item --omit-empty=field

Omit a particular field from the output if it is empty.

=item --comma

=item --no-comma

Whether to place a comma after the final field of each BibTeX entry.
[default=yes]

=item --generate-keys

=item --no-generate-keys

[default=yes]

=item --isbn13=INT

=item --isbn-sep=STR

[default=-]

=item --escape-acronyms

=item --no-escape-acronyms

[default=yes]

=item --no-encode=STR

=item --no-collapse=STR

(TODO: remove no-collapse?)

=item --field=STR

=cut

############
# Options
############
#
# Key: Keep vs generate
#
# Author, Editor: title case, initialize, last-first
# Author, Editor, Affiliation(?): List of renames
# Booktitle, Journal, Publisher*, Series, School, Institution, Location*, Edition*, Organization*, Publisher*, Address*, Language*:
#  List of renames (regex?)
#
# Title
#  Captialization: Initialisms, After colon, list of proper names
#
# ISSN: Print vs Electronic
# Keywords: ';' vs ','

# TODO:
#  author as editors?
#  detect fields that are already de-unicoded (e.g. {H}askell or $p$)
#  move copyright from abstract to copyright field
#  address based on publisher
#  follow jstor links to original publisher
#  add abstract to jstor
#  get PDF
#END TODO

# TODO: omit type-regex field-regex (existing entry is in scope)

# Warn about non-four-digit year
# Omit:class/type
# Include:class/type
# no issn, no isbn
# title-case after ":"
# Warn if first alpha after ":" is not capitalized
# Flag about whether to Unicode, HTML, or LaTeX encode
# purify_string
# Warning on duplicate names

#my %RANGE = map {($_,1)} qw(chapter month number pages volume year);
#my @REQUIRE_FIELDS = (...); # per type (optional regex on value)
#my @RENAME

sub string_flag {
    my ($name, $HASH) = @_;
    ("$name=s" => sub { $HASH->{$_[1]} = 1 },
     "no-$name=s" => sub { delete $HASH->{$_[1]} });
}

my @valid_names = ([]);
for (<DATA>) {
    chomp;
    if (m/^\s*$/) { push @valid_names, [] }
    else { push @{$valid_names[$#valid_names]}, new Text::BibTeX::Name($_) }
}
@valid_names = map { @{$_} ? ($_) : () } @valid_names;

my ($BIBTEX, $DEBUG, $GENERATE_KEY, $ISBN13, $ISBN_SEP, $COMMA, $ESCAPE_ACRONYMS) =
   (      0,      0,             1,       0,       '-',      1,                1);
my (@EXTRA_FIELDS, %NO_ENCODE, %NO_COLLAPSE, %OMIT, %OMIT_EMPTY);

GetOptions(
    'bibtex!' => \$BIBTEX,
    'debug!' => \$DEBUG,
    'field=s' => sub { push @EXTRA_FIELDS, $_[1] },
#    #no-defaults
    'generate-keys!' => \$GENERATE_KEY,
    'isbn13=i' => \$ISBN13,
    'isbn-sep=s' => $ISBN_SEP,
    'comma!' => \$COMMA,
    string_flag('no-encode', \%NO_ENCODE),
    string_flag('no-collapse', \%NO_COLLAPSE), # Whether to collapse contingues whitespace
    string_flag('omit', \%OMIT),
    string_flag('omit_empty', \%OMIT_EMPTY),
    'escape-acronyms!' => \$ESCAPE_ACRONYMS
    );

my $fixer = Text::BibTeX::Fix->new(
    valid_names => [@valid_names],
    debug => $DEBUG,
    known_fields => [@EXTRA_FIELDS],
    isbn13 => $ISBN13,
    isbn_sep => $ISBN_SEP,
    final_comma => $COMMA,
    no_encode => \%NO_ENCODE,
    no_collapse => \%NO_COLLAPSE,
    omit => \%OMIT,
    omit_empty => \%OMIT_EMPTY,
    escape_acronyms => $ESCAPE_ACRONYMS);

my @entries;

if ($BIBTEX) {
# TODO: whether to re-scrape bibtex
    my $file = new Text::BibTeX::File "<-";
    while (my $entry = new Text::BibTeX::Entry $file) {
#    bib_scrape_url = dx.doi if doi and not bib_scrape_url
#    $x->exists('doi') ? "http://dx.doi.org/".doi_clean($x->get('doi')) :
#        $x->exists('bib-scrape-url') ? $x->get('bib-scrape-url') : warn "";
#    push @entries, ...;

#TODO(?): decode utf8
        print $entry, "\n";
        push @entries, $entry;
    }
}

for (@ARGV) {
    my $entry = new Text::BibTeX::Entry;
    $_ =~ s[^doi:][http://dx.doi.org/]i;
    $entry->set('bib_scrape_url', $_);
    push @entries, $entry;
}

for my $old_entry (@entries) {
    my $entry = $old_entry->exists('bib_scrape_url') ?
        Text::BibTeX::Scrape::scrape($old_entry->get('bib_scrape_url')) :
        $old_entry;
# TODO: whether to fix
    print $fixer->fix($entry);
}

__DATA__

Hinze, Ralf

Jeuring, Johan

McBride, Conor

McBride, Nicole

McKinna, James

Uustalu, Tarmo

Wazny, Jeremy

Shan, Chung-chieh

Kiselyov, Oleg

Tolmach, Andrew

Leroy, Xavier

Chitil, Olaf

Oliveira, Bruno C. d. S.
Oliveira, Bruno

Jeremy Gibbons

Carette, Jacques

Fischer, Sebastian

de Paiva, Valeria

Kameyama, Yukiyoshi

Nykänen, Matti

Sperber, Michael

Dybvig, R. Kent

Flatt, Matthew

van Straaten, Anton
Van Straaten, Anton

Findler, Robby

Matthews, Jacob

van Noort, Thomas

Rodriguez Yakushev, Alexey

Holdermans, Stefan

Heeren, Bastiaan

Magalhães, José Pedro

Cebrián, Toni

Arbiser, Ariel

Miquel, Alexandre

Ríos, Alejandro

Barthe, Gilles

Dybjer, Peter

Thiemann, Peter

Heintze, Nevin

McAllester, David

Arisholm, Erik

Briand, Lionel C.

Hove, Siw Elisabeth

Labiche, Yvan

Chen, Yangjun

Chen, Yibin

Endrullis, Jörg

Hendriks, Dimitri

Klop, Jan Willem

Place, Thomas

Segoufin, Luc

Goubault-Larrecq, Jean

Pantel, Patrick

Philpot, Andrew

Hovy, Eduard

Geffert, Viliam

Pighizzini, Giovanni

Mereghetti, Carlo

Wickramaratna, Kasun

Kubat, Miroslav

Minnett, Peter

Geffert, Viliam

Pighizzini, Giovanni

Mereghetti, Carlo

Torta, Gianluca

Torasso, Pietro

Blanqui, Frédéric

Abbott, Michael

Altenkirch, Thorsten

Ghani, Neil

Valmari, Antti

Sevinç, Ender

Coşar, Ahmet

Cîrstea, Corina

Kurz, Alexander

Pattinson, Dirk

Schröder, Lutz

Venema, Yde

Shih, Yu-Ying

Chao, Daniel

Kuo, Yu-Chen

Baccelli, François

Błaszczyszyn, Bartłomiej

Mühlethaler, Paul

Datta, Ajoy K.

Larmore, Lawrence L.

Vemula, Priyanka

Alhadidi, D[ima]
Alhadidi, D.

Belblidia, N[adia]
Belblidia, N.

Debbabi, M[ourad]
Debbabi, M.

Bhattacharya, P[rabir]
Bhattacharya, P.

Strogatz, Steven H.

Lin, Chun-Jung

Smith, David

Löh, Andres

Hagiya, Masami

Wadler, Philip

Cousot, Patrick
Cousot, Radhia

van Noort, Thomas
Van Noort, Thomas

Peyton Jones, Simon
