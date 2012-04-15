#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use WWW::Mechanize;
use Text::BibTeX;
use Text::BibTeX qw(:subs);
use Text::BibTeX::Value;
use Text::BibTeX::Name;
use Text::BibTeX::Scrape;
use Text::BibTeX::Fix;
use HTML::Entities qw(decode_entities);
use Encode;

use Text::RIS;
use Text::MetaBib;
use Text::BibTeX::Months qw(num2month);

use Getopt::Long qw(:config auto_version auto_help);

############
# Options
############
#

$main::VERSION=1.0;
my ($BIBTEX, $DEBUG);

GetOptions('bibtex!' => \$BIBTEX, 'debug!' => \$DEBUG);


############
# Options
############
#
# Comma at end
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
#
#

# TODO:
#  abstract:
#  - paragraphs: no marker but often we get ".<Uperchar>" or "<p></p>"
#  - pass it through paragraph fmt
#  author as editors?
#  Put upper case words in {.} (e.g. IEEE)
#  detect fields that are already de-unicoded (e.g. {H}askell or $p$)
#  move copyright from abstract to copyright field
#  address based on publisher
#END TODO

# TODO: omit type-regex field-regex (existing entry is in scope)

# Warn about non-four-digit year
# Omit:class/type
# Include:class/type
# no issn, no isbn
# SIGPLAN
# title-case after ":"
# Warn if first alpha after ":" is not capitalized
# Flag about whether to Unicode, HTML, or LaTeX encode
# purify_string

## TODO: per type
## Doubles as field order
#my @KNOWN_FIELDS = qw(
#      author editor affiliation title
#      howpublished booktitle journal volume number series jstor_issuetitle
#      type jstor_articletype school institution location
#      chapter pages articleno numpages
#      edition month year issue_date jstor_formatteddate
#      organization publisher address
#      language isbn issn doi eid acmid url eprint bib_scrape_url
#      note annote keywords abstract copyright);
#
#my ($DEBUG, $GENERATE_KEY, $COMMA, $ESCAPE_ACRONYMS) = (0, 1, 1, 1);
#my ($ISBN13, $ISBN_SEP) = (0, '-');
#my %NO_ENCODE = map {($_,1)} qw(doi url eprint bib_scrape_url);
#my %NO_COLLAPSE = map {($_,1)} qw(note annote abstract);
#my %RANGE = map {($_,1)} qw(chapter month number pages volume year);
#my %OMIT = (); # per type (optional regex on value)
#my %OMIT_EMPTY = map {($_,1)} qw(abstract issn doi); # per type
##my @REQUIRE_FIELDS = (...); # per type (optional regex on value)
##my @RENAME
#
#sub string_no_flag {
#    my ($name, $HASH) = @_;
#    ("$name=s" => sub { delete $HASH->{$_[1]} },
#     "no-$name=s" => sub { $HASH->{$_[1]} = 1 });
#}
#
#sub string_flag {
#    my ($name, $HASH) = @_;
#    ("$name=s" => sub { $HASH->{$_[1]} = 1 },
#     "no-$name=s" => sub { delete $HASH->{$_[1]} });
#}
#
#GetOptions(
#    'field=s' => sub { push @KNOWN_FIELDS, $_[1] },
#    'debug!' => \$DEBUG,
#    #no-defaults
#    'generate-keys!' => \$GENERATE_KEY,
#    'isbn13!' => \$ISBN13,
#    'isbn-sep=s' => $ISBN_SEP,
#    'comma!' => \$COMMA,
#    string_no_flag('encode', \%NO_ENCODE),
#    string_no_flag('collapse', \%NO_COLLAPSE), # Whether to collapse contingues whitespace
#    string_flag('omit', \%OMIT),
#    string_flag('omit', \%OMIT_EMPTY),
#    'escape-acronyms!' => \$ESCAPE_ACRONYMS
#    );


=head1 SYNOPSIS

bibscrape [options] <url> ...

=head2 OPTIONS

=item --bibtex

    Take input as BibTeX data from standard input instead of the
    default of taking input as URLs from the command line.

=item --debug

    Print debug data (TODO: make it verbose and go to STDERR)

=cut

### TODO
=head1 SYNOPSIS

bibscrape [options] <url> ...

=head2 OPTIONS

=item --omit=field

    Omit a particular field from the output.

=item --debug

    Print debug data (TODO: make it verbose and go to STDERR)

=cut


# TODO:
#  get PDF
#  abstract:
#  - paragraphs: no marker but often we get ".<Uperchar>" or "<p></p>"
#  author as editors?
#  follow jstor links to original publisher
#  add abstract to jstor
#END TODO

my @valid_names = ([]);
for (<DATA>) {
    chomp;
    if (m/^\s*$/) { push @valid_names, [] }
    else { push @{$valid_names[$#valid_names]}, new Text::BibTeX::Name($_) }
}
@valid_names = map { @{$_} ? ($_) : () } @valid_names;

my @entries;

if ($BIBTEX) {
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
    $entry->set('bib_scrape_url', $_);
    push @entries, $entry;
}

my $fixer = Text::BibTeX::Fix->new(valid_names => [@valid_names]);
for my $old_entry (@entries) {
    my $url = $old_entry->get('bib_scrape_url');
    print $old_entry->print_s() and next unless $url;
#    print encode('utf8', Text::BibTeX::Scrape::scrape($url)->print_s());
    my $entry = Text::BibTeX::Scrape::scrape($url);
#    $entry->set_key(encode('utf8', $entry->key));
#    $entry->set($_, encode('utf8', $entry->get($_)))
#        for ($entry->fieldlist());
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
