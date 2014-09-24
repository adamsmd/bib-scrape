#!/usr/bin/env perl

use warnings;
use strict;
$|++;

# Silence a known warning in Text::BibTeX::Value
BEGIN {
    my $old_warn = $SIG{__WARN__};
    $SIG{__WARN__} = sub {
        warn @_ unless $_[0] =~
            m[^UNIVERSAL->import is deprecated and will be removed in a future perl.*Text/BibTeX/Value.pm line \d+\.];
    };
}

use Getopt::Long qw(:config auto_version auto_help);

use Text::BibTeX qw(:metatypes);
use Text::BibTeX::Fix;
use Text::BibTeX::Name;
use Text::BibTeX::Scrape;

$main::VERSION='14.09.24';

=head1 SYNOPSIS

bib-scrape.pl [options] <url> ...

=head2 INPUTS

=item <url>

The url of the publisher's page for the paper to be scraped.
Standard URL formats such as 'http://...' can be used.
The non-standard URL format 'doi:...' can also be used.
May be prefixed with '{key}' in order to specify an explicit key.

=item --input=<file>

Take BibTeX data from <file> to rescrape or fix.
If <file> is '-', then read from STDIN.

WARNING: "junk" and malformed entities will be omitted from the output
(This is an upstream problem with the libraries we use.)

=item --names=<file>

Add <file> to the list of name files used to canonicalize author names.
If <file> is the empty string, clears the list.

See the L</NAME FILE> section for details on the format of name files.

=item --action=<file>

Add <file> to the list of action files used to canonicalize fields.
If <file> is the empty string, clears the list.

See the L</ACTION FILE> section for details on the format of action files.

=head2 OPERATING MODES

=item --debug, --no-debug [default=no]

Print debug data

=item --fix, --no-fix [default=yes]

Fix common mistakes in the BibTeX

=item --scrape, --no-scrape [default=yes]

Scrape BibTeX entry from the publisher's page

=head2 GENERAL OPTIONS

=item --isbn13=<mode> [default=0]

If <mode> is a positive integer, then always use ISBN-13 in the output.
If negative, then use ISBN-10 when possible.
If zero, then preserve the original format of an ISBN.

=item --isbn-sep=<sep> [default=-]

Use <sep> to separate parts of an ISBN.
Use an empty string to specify no separator.

=item --issn=<kind> [default=both]

When both a print and an online ISSN are available, use only the print
ISSN if <kind> is 'print, only the online ISSN if <kind> is 'online',
or both if <kind> is 'both'.

=item --comma, --no-comma [default=yes]

Place a comma after the final field of a BibTeX entry.

=item --escape-acronyms, --no-escape-acronyms [default=yes]

In titles, enclose sequences of two or more uppercase letters (i.e.,
an acronym) in braces to that BibTeX preserves their case.

=head2 Per FIELD OPTIONS

=item --field=<field>

Add a field to the list of known BibTeX fields.

=item --no-encode=<field>

Add a field to the list of fields that should not be LaTeX encoded.
By default this includes doi, url, eprint, and bib_scrape_url, but if
this flag is specified on the command line, then only those explicitly
listed on the command line are included.

=item --no-collapse=<field>

Add a filed to the list of fields that should not have their
white space collapsed.

=item --omit=<field>

Omit a particular field from the output.

=item --omit-empty=<field>

Omit a particular field from the output if it is empty.

=head2 NAME FILES

A name file specifies the correct form for author names.
Any name that is not of the form "FIRST LAST" is suspect unless
it is in a name file.

A name file is plain text in Unicode format.
In a name file, any line starting with # is a comment.
Blank or whitespace-only lines separate blocks, and
blocks consist of one or more lines.
The first line is the canonical form of a name.
Lines other than the first one are aliases that should be converted to the
canonical form.

When searching for the canonical form of a name, case distinctions and
the divisions of the name into parts (e.g. first vs last name) are
ignored as publishers often get these wrong (e.g., "Van Noort" will
match "van Noort" and "Jones, Simon Peyton" will match "Peyton Jones,
Simon").

The default name file provides several examples and recommended practices.

=head2 ACTION FILES

An action file specifies transformations to be applied to each field.

This file is just Perl code.
On entry, $FIELD will contain the name of the current BibTeX field,
and $_ will contain the contents of the field.
The value of $_ at the end of this file will be stored back in the field.
If it is undef then the field will be deleted.

TIP: Remember to check $FIELD so you transform only the correct fields.

TIP: Remember to put "\b", "/g" and/or "/i" on substitutions if appropriate.

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

# TODO:
# ALWAYS_GEN_KEY
#$PREFER_NEW 1 = use new when both new and old have a key
#$ADD_NEW 1 = use new when only new has key
#$REMOVE_OLD 1 = not use old when only new has key

#my %RANGE = map {($_,1)} qw(chapter month number pages volume year);
#my @REQUIRE_FIELDS = (...); # per type (optional regex on value)
#my @RENAME

# TODO:
# preserve key if from bib-tex?
# warn about duplicate author names

sub string_flag {
    my ($name, $HASH) = @_;
    ("$name=s" => sub { $HASH->{$_[1]} = 1 },
     "no-$name=s" => sub { delete $HASH->{$_[1]} });
}

my ($DEBUG, $SCRAPE, $FIX) =
   (      0,      1,    1);
my ($ISBN13, $ISBN_SEP, $ISSN, $COMMA, $ESCAPE_ACRONYMS) =
   (      0,       '-','both',      1,                1);
my (@NAME_FILE) = ('names.txt');
my (@FIELD_ACTION_FILE) = ('action.txt');
my (@INPUT, @EXTRA_FIELDS, %NO_ENCODE, %NO_COLLAPSE, %OMIT, %OMIT_EMPTY);

GetOptions(
    # Input options
    'input=s' => sub { push @INPUT, $_[1] },
    'names=s' => sub { if ($_[1] eq '') { @NAME_FILE=() }
                       else { push @NAME_FILE, $_[1] } },
    'action=s' => sub { if ($_[1] eq '') { @FIELD_ACTION_FILE=() }
                        else { push @FIELD_ACTION_FILE, $_[1] } },

    # Operating modes
    # TODO: make debug be verbose and go to STDERR
    'debug!' => \$DEBUG,
    'fix!' => \$FIX,
    'scrape!' => \$SCRAPE,

    # General options
    # TODO: no-defaults
    'isbn13=i' => \$ISBN13,
    'isbn-sep=s' => \$ISBN_SEP,
    'issn' => \$ISSN,
    'comma!' => \$COMMA,
    'escape-acronyms!' => \$ESCAPE_ACRONYMS,

    # Field specific options
    'field=s' => sub { push @EXTRA_FIELDS, $_[1] },
    string_flag('no-encode', \%NO_ENCODE),
    string_flag('no-collapse', \%NO_COLLAPSE), # Whether to collapse contiguous whitespace
    string_flag('omit', \%OMIT),
    string_flag('omit-empty', \%OMIT_EMPTY),
    );

my $fixer = Text::BibTeX::Fix->new(
    valid_names => [map {read_valid_names($_)} @NAME_FILE],
    field_action => join('\n', slurp_file(@FIELD_ACTION_FILE)),
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
                # Try to find a URL to scrape
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

    # TODO: warn if not exists bib_scrape_url
    my $entry = (($old_entry->exists('bib_scrape_url') && $SCRAPE) ?
        Text::BibTeX::Scrape::scrape($old_entry->get('bib_scrape_url')) :
        $old_entry);
    $entry->set_key($old_entry->key());
    print $FIX ? $fixer->fix($entry) : $entry->print_s;
}

sub read_valid_names {
    my ($name_file) = @_;
    open(NAME_FILE, "<", $name_file) || die "Could not open name file '$name_file': $!";
    my @names = ([]);
    for (<NAME_FILE>) {
        chomp;
        if (m/^#/) { }
        elsif (m/^\s*$/) { push @names, [] }
        else { push @{$names[$#names]}, new Text::BibTeX::Name($_) }
    }
    close NAME_FILE;
    return map { @{$_} ? ($_) : () } @names;
}

sub slurp_file {
    my @files = ();
    for (@_) {
        open(FILE, "<", $_) || die "Could not open file '$_': $!";
        push @files, join('', <FILE>);
        close FILE;
    }
    return @files;
}
