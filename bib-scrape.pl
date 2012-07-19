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
    if (m/^#/) { }
    elsif (m/^\s*$/) { push @valid_names, [] }
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

# Often publishers leave out the middle name even when it is a critial
# part of the name

Oliveira, Bruno C. d. S.
Oliveira, Bruno

Dybvig, R. Kent
Dybvig, R.

# We can't assume a three part name is "first middle last" as some
# people have two words in their last name.  Further, publishers often
# get this wrong (e.g. "Jones, Simon Peyton") Thus we explicitly
# specify those names.

Rodriguez Yakushev, Alexey

Peyton Jones, Simon

Magalhães, José Pedro

Hernán, Miguel Ángel

Klop, Jan Willem

Hove, Siw Elisabeth

Strogatz, Steven H.

# Be careful with last names containing "van", "von", "di", "de", etc.
# Sometimes these parts of the names are capitalized, while other
# times they are not.  Always double check how the particular author
# spells it.
#
# Note that when they are lower case, bibtex treats them as a seperate
# part of the name, but when they are upper case, bibtex treats them
# as part of the last name.  Thus sometimes case insensitive match
# isn't enough to find the name.
Van Noort, Thomas

van Straaten, Anton
Van Straaten, Anton

van Noort, Thomas

Van Horn, David

Van Hentenryck, Pascal

Di Gianantonio, Pietro

de Paiva, Valeria

De Bosschere, Koen

DeBiasio, Louis

# Sometimes the abbreviated form of a name is what was actually written
# on the article, but other times it's due to the publisher reporting
# the wrong data.  Here we can correct the publisher's error, mark the
# abriviation as correct, or use "[]" to give the full name.  (You can
# also just change it to the full name but then your bibliography
# would be lying if the original paper used the abbreviated name.)

Kierstead, H. A.
Kierstead, H.A.

Frigo, Matteo
Frigo, M.

Johnson, Steven G.
Johnson, S.G.

Rawlings, Christopher J.
Rawlings, C.J.

Clark, Dominic A.
Clark, D.A.

Barton, Geoffrey J.
Barton, G.J.

Archer, Iain
Archer, I.

Saldanha, José W.
Saldanha, J.W.

Singh, Gulab
Singh, G.

Venkataraman, G.

kumar (\emph{sic}), V.
kumar, V.

Rao, Y. S.
Rao, Y.S.

Snehmani

Riordon, J. S.

Aho, A[lfred] V.
Aho, A. V.

Hopcroft, J[ohn] E.
Hopcroft, J. E.

Ullman, J[effrey] D.
Ullman, J. D.

Alhadidi, D[ima]
Alhadidi, D.

Belblidia, N[adia]
Belblidia, N.

Debbabi, M[ourad]
Debbabi, M.

Bhattacharya, P[rabir]
Bhattacharya, P.

Streicher, Th[omas]
Streicher, Th.
Reus, B[ernhard]
Reus, B.


# Cambridge press returns names in all upper case.  This forces us to
# list lots of extra names that are in the "first last" form we would
# normally automatically recognize.

McBride, Conor

McKinna, James

Hinze, Ralf

Jeuring, Johan

Uustalu, Tarmo

Wazny, Jeremy

Kameyama, Yukiyoshi

Kiselyov, Oleg

Shan, Chung-chieh

Holdermans, Stefan

Heeren, Bastiaan

Carette, Jacques

Cebrián, Toni

Fischer, Sebastian

Arbiser, Ariel

Miquel, Alexandre

Ríos, Alejandro

Sperber, Michael

Flatt, Matthew

Findler, Robby

Matthews, Jacob

Gibbons, Jeremy

Chitil, Olaf

Nykänen, Matti
