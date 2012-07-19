#!/usr/bin/env perl

use warnings;
use strict;
$|++;

use Getopt::Long qw(:config auto_version auto_help);

use Text::BibTeX qw(:metatypes);
use Text::BibTeX::Fix;
use Text::BibTeX::Name;
use Text::BibTeX::Scrape;

$main::VERSION='1.1';

=head1 SYNOPSIS

bib-scrape.pl [options] <url> ...

=head2 URL

The url of the publisher's page for the paper to be scraped.

Standard URL formats such as 'http://...' are allowed,
but so is the format 'doi:...'.

May be prefixed with '{key}' in order to specify an explicit key.

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

=item --input=FILE

FILE may be "-" to indicate stdin

WARNING: "junk" and malformed entities will be omitted from the output
(This is an upstream problem with the libraries we use.)

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
#  follow jstor links to original publisher
#  add abstract to jstor
#  get PDF
#END TODO

# TODO: omit type-regex field-regex (existing entry is in scope)

# Omit:class/type
# Include:class/type
# no issn, no isbn
# title-case after ":"
# Warn if first alpha after ":" is not capitalized
# Flag about whether to Unicode, HTML, or LaTeX encode
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

my ($DEBUG, $SCRAPE, $KEEP_OLD, $FIX) =
   (      0,      1,         1,    1);
my ($GENERATE_KEY, $ISBN13, $ISBN_SEP, $ISSN, $COMMA, $ESCAPE_ACRONYMS) =
   (             1,       0,      '-','both',      1,                1);
my (@INPUT, @EXTRA_FIELDS, %NO_ENCODE, %NO_COLLAPSE, %OMIT, %OMIT_EMPTY);

GetOptions(
    'debug!' => \$DEBUG,
    'fix!' => \$FIX,
    'field=s' => sub { push @EXTRA_FIELDS, $_[1] },
    'input=s' => sub { push @INPUT, $_[1] },
#    #no-defaults
    'isbn13=i' => \$ISBN13,
    'isbn-sep=s' => \$ISBN_SEP,
    'issn' => \$ISSN,
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
    issn => $ISSN,
    final_comma => $COMMA,
    no_encode => \%NO_ENCODE,
    no_collapse => \%NO_COLLAPSE,
    omit => \%OMIT,
    omit_empty => \%OMIT_EMPTY,
    escape_acronyms => $ESCAPE_ACRONYMS);
# ? ISSN (Print, Online, Both)
# preserve key if from bib-tex?
# warn about duplicate author names

# TODO: whether to re-scrape bibtex
for my $filename (@INPUT) {
    my $bib = new Text::BibTeX::File $filename;
    # TODO: print "junk" between entities

    until ($bib->eof()) {
        my $entry = new Text::BibTeX::Entry $bib;
        next unless defined $entry and $entry->parse_ok;

        if (not $entry->metatype == BTE_REGULAR) {
            print $entry->print_s;
        } else {
            if (not $entry->exists('bib_scrape_url')) {
                if ($entry->exists('doi') and $entry->get('doi') =~ m[http://[^/]+/(.*)]i) {
                    (my $url = $1) =~ s[DOI:\s*][]ig;
                    $entry->set('bib_scrape_url', "http://dx.doi.org/$url");
                } elsif ($entry->exists('url') and $entry->get('url') =~ m[^http://dx.doi.org/.*$]) {
                    $entry->set('bib_scrape_url', $entry->get('url'));
                }
            }
###TODO(?): decode utf8
            scrape_and_fix_entry($entry);
        }
    }
}

for (@ARGV) {
    my $entry = new Text::BibTeX::Entry;
    $entry->set_key($1) if $_ =~ s[^\{([^}]*)\}][];
    $_ =~ s[^doi:][http://dx.doi.org/]i;
    $entry->set('bib_scrape_url', $_);
    scrape_and_fix_entry($entry);
}

sub scrape_and_fix_entry {
    my ($old_entry) = @_;

#    warn if not exists bib_scrape_url
    my $entry = (($old_entry->exists('bib_scrape_url') && $SCRAPE) ?
        Text::BibTeX::Scrape::scrape($old_entry->get('bib_scrape_url')) :
        $old_entry);
#    print $entry->print_s, "\n";
    $entry->set_key($old_entry->key());
# ALWAYS_GEN_KEY
#no-SCRAPE = 0, 0, 0
#SCRAPE = 1, 1, 1
#    if ($KEEP_OLD) {
#$PREFER_NEW 1
#$ADD_NEW 1
#$REMOVE_OLD 1
    print $FIX ? $fixer->fix($entry) : $entry->print_s;
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

van Straaten, Anton
Van Straaten, Anton

van Noort, Thomas
Van Noort, Thomas

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
