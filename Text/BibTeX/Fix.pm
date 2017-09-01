package Text::BibTeX::Fix;

use warnings;
use strict;

use Carp;
use Safe;

use Encode;
use HTML::Entities qw(decode_entities);
use Locale::Language qw(code2language);
use Scalar::Util qw(blessed);
use TeX::Unicode;
use Text::ISBN;
use XML::Parser;

use Text::BibTeX;
use Text::BibTeX qw(:subs :nameparts :joinmethods);
use Text::BibTeX::Months qw(str2month num2month);
use Text::BibTeX::Name;
use Text::BibTeX::NameFormat;
use Text::BibTeX::Value;

use vars ('$FIELD'); # Used to communicate with $self->field_action

sub scalar_flag {
    my ($obj, $options, $field, $default) = @_;
    $obj->{$field} = exists $options->{$field} ? $options->{$field} : $default;
    delete $options->{$field};
}

sub array_flag {
    my ($obj, $options, $field, @default) = @_;
    $obj->{$field} = [@default];
    push @{$obj->{$field}}, @{$options->{$field}} if exists $options->{$field};
    delete $options->{$field} if exists $options->{$field};
}

sub hash_flag {
    my ($obj, $options, $field, @default) = @_;
    $obj->{$field} = { map { ($_, 1) } @default };
    if (exists $options->{$field}) {
        for (keys %{$options->{$field}}) {
            if ($options->{$field}->{$_}) { $obj->{$field}->{$_} = 1 }
            else { delete $obj->{$field}->{$_} }
        }
        delete $options->{$field};
    }
}

use Class::Struct 'Text::BibTeX::Fix::Impl' => {
  known_fields => '@', valid_names => '@',
  debug => '$', final_comma => '$', escape_acronyms => '$',
  isbn => '$', isbn13 => '$', isbn_sep => '$', issn => '$',
  no_encode => '%', no_collapse => '%', omit => '%', omit_empty => '%',
  field_action => '$',
};

sub Text::BibTeX::Fix::new {
    my ($class, %options) = @_;

    my $cfg = {};

# TODO: per type
# Doubles as field order
    array_flag($cfg, \%options, 'known_fields', qw(
      author editor affiliation title
      howpublished booktitle journal volume number series jstor_issuetitle
      type jstor_articletype school institution location
      chapter pages articleno numpages
      edition day month year issue_date jstor_formatteddate
      organization publisher address
      language isbn issn doi eid acmid url eprint bib_scrape_url
      note annote keywords abstract copyright));
    array_flag($cfg, \%options, 'valid_names', qw());

    scalar_flag($cfg, \%options, 'debug', 0);
    scalar_flag($cfg, \%options, 'final_comma', 1);
    scalar_flag($cfg, \%options, 'escape_acronyms', 1);
    scalar_flag($cfg, \%options, 'isbn', 'both');
    scalar_flag($cfg, \%options, 'isbn13', 0);
    scalar_flag($cfg, \%options, 'isbn_sep', '-');
    scalar_flag($cfg, \%options, 'issn', 'both');
    scalar_flag($cfg, \%options, 'field_action', '');

    hash_flag($cfg, \%options, 'no_encode', qw(doi url eprint bib_scrape_url));
    hash_flag($cfg, \%options, 'no_collapse', qw());
    hash_flag($cfg, \%options, 'omit', qw());
    hash_flag($cfg, \%options, 'omit_empty', qw(abstract issn doi keywords));

    croak("Unknown option: $_") for keys %options;

    return Text::BibTeX::Fix::Impl->new(%$cfg);
}

sub Text::BibTeX::Fix::Impl::fix {
    my ($self, $entry) = @_;

    # TODO: $bib_text =~ s/^\x{FEFF}//; # Remove Byte Order Mark
    # Fix any unicode that is in the field values
#    $entry->set_key(decode('utf8', $entry->key));
#    $entry->set($_, decode('utf8', $entry->get($_)))
#        for ($entry->fieldlist());

    # Doi field: remove "http://hostname/" or "DOI: "
    $entry->set('doi', $entry->get('url')) if (
        not $entry->exists('doi') and
        ($entry->get('url') || "") =~ m[^http(s?)://(dx.)?doi.org/.*$]);
    update($entry, 'doi', sub { s[http(s?)://[^/]+/][]i; s[DOI:\s*][]ig; });

    # Page numbers: no "pp." or "p."
    # TODO: page fields
    # [][pages][pp?\.\s*][]ig;
    update($entry, 'pages', sub { s[pp?\.\s*][]ig; });

    # [][number]rename[issue][.+][$1]delete;
    # rename fields
    for (['issue', 'number'], ['keyword', 'keywords']) {
        # Fix broken field names (SpringerLink and ACM violate this)
        if ($entry->exists($_->[0]) and
            (not $entry->exists($_->[1]) or $entry->get($_->[0]) eq $entry->get($_->[1]))) {
            $entry->set($_->[1], $entry->get($_->[0]));
            $entry->delete($_->[0]);
        }
    }

    # Ranges: convert "-" to "--"
    # TODO: option for numeric range
    # TODO: might misfire if "-" doesn't represent a range, Common for tech report numbers
    for my $key ('chapter', 'month', 'number', 'pages', 'volume', 'year') {
        update($entry, $key, sub { s[\s*[-\N{U+2013}\N{U+2014}]+\s*][--]ig; });
        update($entry, $key, sub { s[n/a--n/a][]ig; $_ = undef if $_ eq "" });
        update($entry, $key, sub { s[\b(\w+)--\1\b][$1]ig; });
        update($entry, $key, sub { s[(^| )(\w+)--(\w+)--(\w+)--(\w+)($|,)][$1$2-$3--$4-$5$6]g });
        update($entry, $key, sub { s[\s+,\s+][, ]ig; });
    }

    check($entry, 'pages', "suspect page number", sub {
        my $page = qr[\d+ | # Simple digits
                      \d+--\d+ |

                      [XVIxvi]+ | # Roman digits
                      [XVIxvi]+--[XVIxvi]+ |
                      [XVIxvi]+-\d+ | # Roman digits dash digits
                      [XVIxvi]+-\d+--[XVIxvi]+-\d+ |

                      \d+[a-z] | # Digits plus letter
                      \d+[a-z]--\d+[a-z] |
                      \d+[.:/]\d+ | # Digits sep Digits
                      \d+([.:/])\d+--\d+\1\d+ |

                      f\d+ | # "Front" page
                      f\d+--f\d+
                      ]x;
        m[^$page(, $page)*$];
          });

    check($entry, 'volume', "suspect volume", sub {
        m[^\d+$] || m[^\d+-\d+$] || m[^[A-Z]-\d+$] || m[^\d+-[A-Z]$] });

    check($entry, 'number', "suspect number", sub {
        m[^\d+$] || m[^\d+--\d+$] || m[^\d+(/\d+)*$] || m[^\d+es$] ||
        m[^Special Issue \d+(--\d+)?$] || m[^S\d+$]});

    # TODO: Keywords: ';' vs ','

    my $isbn_re = qr[(?:\d+-)?\d+-\d+-\d+-[0-9X]];
    update($entry, 'isbn', sub {
        if (m[^($isbn_re) \(Print\) ($isbn_re) \(Online\)$]) {
            if ($self->isbn eq 'both') {
                $_ = Text::ISBN::canonical($1, $self->isbn13, $self->isbn_sep)
                    . ' (Print) '
                    . Text::ISBN::canonical($2, $self->isbn13, $self->isbn_sep)
                    . ' (Online)';
            } elsif ($self->isbn eq 'print') {
                $_ = Text::ISBN::canonical($1, $self->isbn13, $self->isbn_sep);
            } elsif ($self->isbn eq 'online') {
                $_ = Text::ISBN::canonical($2, $self->isbn13, $self->isbn_sep);
            }
        } elsif (m[^$isbn_re$]) {
            $_ = Text::ISBN::canonical($_, $self->isbn13, $self->isbn_sep);
        } elsif ($_ eq '') { $_ = undef;
        } else { print "WARNING: Suspect ISBN: $_\n"
        }
           });

    my $issn_re = qr[\d\d\d\d-\d\d\d[0-9X]];
    update($entry, 'issn', sub {
        s[\b(\d{4})(\d{3}[0-9X])\b][$1-$2]g;
        if (m[^($issn_re) \(Print\) ($issn_re) \(Online\)$]) {
            if ($self->issn eq 'both') {
                Text::ISBN::valid_issn($1) or print "WARNING: Check sum failed in issn: $1\n";
                Text::ISBN::valid_issn($2) or print "WARNING: Check sum failed in issn: $2\n";
            } elsif ($self->issn eq 'print') {
                Text::ISBN::valid_issn($1) or print "WARNING: Check sum failed in issn: $1\n";
                $_ = $1;
            } elsif ($self->issn eq 'online') {
                Text::ISBN::valid_issn($2) or print "WARNING: Check sum failed in issn: $2\n";
                $_ = $2;
            }
        } elsif (m[^$issn_re$]) {
            Text::ISBN::valid_issn($_) or print "WARNING: Check sum failed in issn: $_\n"
        } elsif ($_ eq '') { $_ = undef
        } else { print "WARNING: Suspect ISSN: $_\n" }
           });

    # TODO: Author, Editor, Affiliation: List of renames
# Booktitle, Journal, Publisher*, Series, School, Institution, Location*, Edition*, Organization*, Publisher*, Address*, Language*:

    # Change language codes (e.g., "en") to proper terms (e.g., "English")
    update($entry, 'language', sub { $_ = code2language($_) if defined code2language($_) });
#  List of renames (regex?)

    if ($entry->exists('author')) { canonical_names($self, $entry, 'author') }
    if ($entry->exists('editor')) { canonical_names($self, $entry, 'editor') }

#D<onald|.=[onald]> <E.|> Knuth
#
#D(onald|.) (E.) Knuth
#D E Knuth
#
#D[onald] Knuth
#D Knuth
#
#D[onald] [E.] Knuth
#D Knuth
#
#Donald Knuth
#D[onald] Knuth
#D. Knuth
#Knuth, D.

    # Don't include pointless URLs to publisher's page
    # [][url][http://dx.doi.org/][];
    # TODO: via Omit if matches
    # TODO: omit if ...
    update($entry, 'url', sub {
        $_ = undef if m[^(http(s?)://doi.org/
                         |http(s?)://dx.doi.org/
                         |http(s?)://doi.acm.org/
                         |http(s?)://portal.acm.org/citation.cfm
                         |http(s?)://www.jstor.org/stable/
                         |http(s?)://www.sciencedirect.com/science/article/)]x; } );
    # TODO: via omit if empty
    update($entry, 'note', sub { $_ = undef if $_ eq "" });
    # TODO: add $doi to omit if matches
    # [][note][$doi][]
    # regex delete if looks like doi
    # Fix Springer's use of 'note' to store 'doi'
    update($entry, 'note', sub { $_ = undef if $_ eq ($entry->get('doi') or "") });

    # Eliminate Unicode but not for no_encode fields (e.g. doi, url, etc.)
    for my $field ($entry->fieldlist()) {
        warn "Undefined $field" unless defined $entry->get($field);
        $entry->set($field, latex_encode($entry->get($field)))
            unless exists $self->no_encode->{$field};
    }

    # Canonicalize series: PEPM'97 -> PEPM~'97 (must be after Unicode escaping
    update($entry, 'series', sub { s/([[:upper:]]+) *'(\d+)/$1~'$2/g; });

    # Collapse spaces and newlines
    $self->no_collapse->{$_} or update($entry, $_, sub {
        s[\s*$][]; # remove trailing whitespace
        s[^\s*][]; # remove leading whitespace
        s[(\n *){2,}][{\\par}]sg; # BibTeX eats whitespace so convert "\n\n" to paragraph break
        s[\s*\n\s*][ ]sg; # Remove extra line breaks
        s[{\\par}][\n{\\par}\n]sg; # Nicely format paragraph breaks
        #s[\s{2,}][ ]sg; # Remove duplicate whitespace
                                       }) for $entry->fieldlist();

    # TODO: Title Capticalization: Initialisms, After colon, list of proper names
    update($entry, 'title', sub { s/((\d*[[:upper:]]\d*){2,})/{$1}/g; }) if $self->escape_acronyms;

    for $FIELD ($entry->fieldlist()) {
        my $compartment = new Safe;
        $compartment->deny_only();
        $compartment->share_from('Text::BibTeX::Fix', ['$FIELD']);
        $compartment->share('$_');
        update($entry, $FIELD, sub { $compartment->reval($self->field_action); });
    }

    # Generate an entry key
    # TODO: Formats: author/editor1.last year title/journal.abbriv
    # TODO: Remove doi?
    if (not defined $entry->key()) {
        my ($name) = ($entry->names('author'), $entry->names('editor'));
        $name = defined $name ?
            purify_string(join("", $name->part('last'))) :
            "anon";
        my $year = $entry->exists('year') ? ":" . $entry->get('year') : "";
        my $doi = $entry->exists('doi') ? ":" . $entry->get('doi') : "";
        #$organization, or key
        $entry->set_key($name . $year . $doi);
    }

    # Use bibtex month macros
    update($entry, 'month', # Must be after field encoding because we use macros
           sub { s[\.($|-)][$1]g; # Remove dots due to abbriviations
                 my @x = map {
                     ($_ eq '/' || $_ eq '-' || $_ eq '--') and [Text::BibTeX::BTAST_STRING, $_] or
                     str2month(lc $_) or
                     m[^\d+$] and num2month($_) or
                     print "WARNING: Suspect month: $_\n" and [Text::BibTeX::BTAST_STRING, $_]}
                   split /\b/;
                 $_ = new Text::BibTeX::Value(@x)});

    # Omit fields we don't want
    # TODO: controled per type or with other fields or regex matching
    $entry->exists($_) and $entry->delete($_) for (keys %{$self->omit});
    $entry->exists($_) and $entry->get($_) eq '' and $entry->delete($_) for (keys %{$self->omit_empty});

    # Year
    check($entry, 'year', "Suspect year", sub { /^\d\d\d\d$/ });

    # Put fields in a standard order.
    for my $field ($entry->fieldlist()) {
        die "Unknown field '$field'\n" unless grep { $field eq $_ } @{$self->known_fields};
        die "Duplicate field '$field' will be mangled" if
            scalar(grep { $field eq $_ } $entry->fieldlist()) >= 2;
    }
    $entry->set_fieldlist([map { $entry->exists($_) ? ($_) : () } @{$self->known_fields}]);

    # Force comma or no comma after last field
    my $str = $entry->print_s();
    $str =~ s[(})(\s*}\s*)$][$1,$2] if $self->final_comma;
    $str =~ s[(}\s*),(\s*}\s*)$][$1$2] if !$self->final_comma;

    return $str;
}


# Based on TeX::Encode and modified to use braces appropriate for BibTeX.
sub latex_encode
{
    use utf8;
    my ($str) = @_;

    # HTML -> LaTeX Codes
    $str = decode_entities($str);
    #$str =~ s[\_(.)][\\ensuremath{\_{$1}}]isog; # Fix for IOS Press
    $str =~ s[<!--.*?-->][]sg; # Remove HTML comments
    $str =~ s[<a [^>]*onclick="toggleTabs\(.*?\)">.*?</a>][]isg; # Fix for Science Direct

    # HTML formatting
    $str =~ s[<([^>]*)\bclass="a-plus-plus"([^>]*)>][<$1$2>]isg; # Remove class annotation
    $str =~ s[<(\w+)\s*>][<$1>]isg; # Removed extra space around simple tags
    $str =~ s[<a( .*?)?>(.*?)</a>][$2]isog; # Remove <a> links
    $str =~ s[<p(| [^>]*)>(.*?)</p>][$2\n\n]isg; # Replace <p> with "\n\n"
    $str =~ s[<par(| [^>]*)>(.*?)</par>][$2\n\n]isg; # Replace <par> with "\n\n"
    $str =~ s[<span style="font-family:monospace\s*">(.*?)</span>][\\texttt{$1}]isg; # Replace monospace spans with \texttt
    $str =~ s[<span class="monospace\s*">(.*?)</span>][\\texttt{$1}]isg; # Replace monospace spans with \texttt
    $str =~ s[<span class="smallcaps\s*">(.*?)</span>][\\textsc{$1}]isg; # Replace small caps spans with \textsc
    $str =~ s[<span class="[^"]*type-small-caps[^"]*">(.*?)</span>][\\textsc{$1}]isg; # Replace small caps spans with \textsc
    $str =~ s[<span class="italic">(.*?)</span>][\\emph{$1}]isg; # TODO: "isog"? \\textit?
    $str =~ s[<span class="bold">(.*?)</span>][\\textbf{$1}]isg; # TODO: "isog"? \\textit?
    $str =~ s[<span class="sup">(.*?)</span>][\\textsuperscript{$1}]isg; # TODO: "isog"? \\textit?
    $str =~ s[<span class="sub">(.*?)</span>][\\textsubscript{$1}]isg; # TODO: "isog"? \\textit?
    $str =~ s[<span class="sc">(.*?)</span>][\\textsc{$1}]isg; # TODO: "isog"?
    $str =~ s[<span class="EmphasisTypeSmallCaps ">(.*?)</span>][\\textsc{$1}]isg;
    $str =~ s[<span( .*?)?>(.*?)</span>][$2]isg; # Remove <span>
    $str =~ s[<span( .*?)?>(.*?)</span>][$2]isg; # Remove <span>
    $str =~ s[<i>(.*?)</i>][\\textit{$1}]isog; # Replace <i> with \textit
    $str =~ s[<italic>(.*?)</italic>][\\textit{$1}]isog; # Replace <italic> with \textit
    $str =~ s[<em [^>]*?>(.*?)</em>][\\emph{$1}]isog; # Replace <em> with \emph
    $str =~ s[<strong>(.*?)</strong>][\\textbf{$1}]isog; # Replace <strong> with \textbf
    $str =~ s[<b>(.*?)</b>][\\textbf{$1}]isog; # Replace <b> with \textbf
    $str =~ s[<tt>(.*?)</tt>][\\texttt{$1}]isog; # Replace <tt> with \texttt
    $str =~ s[<code>(.*?)</code>][\\texttt{$1}]isog; # Replace <code> with \texttt
#    $str =~ s[<small>(.*?)</small>][{\\small $1}]isog; # Replace <small> with \small
    $str =~ s[<sup>(.*?)</sup>][\\textsuperscript{$1}]isog; # Super scripts
    $str =~ s[<supscrpt>(.*?)</supscrpt>][\\textsuperscript{$1}]isog; # Super scripts
    $str =~ s[<sub>(.*?)</sub>][\\textsubscript{$1}]isog; # Sub scripts

    $str =~ s[<img src="http://www.sciencedirect.com/scidirimg/entities/([0-9a-f]+).gif".*?>][@{[chr(hex $1)]}]isg; # Fix for Science Direct
    $str =~ s[<img src="/content/[A-Z0-9]+/xxlarge(\d+).gif".*?>][@{[chr($1)]}]isg; # Fix for Springer Link
    $str =~ s[<email>(.*?)</email>][$1]isg; # Fix for Cambridge

    # MathML formatting
    my $xml = XML::Parser->new(Style => 'Tree');
    $str =~ s[(<mml:math\b[^>]*>.*?</mml:math>)]
             [\\ensuremath{@{[rec(@{$xml->parse($1)})]}}]gs; # TODO: ensuremath (but avoid latex encoding)

    # Trim spaces before NBSP (otherwise they have not effect in LaTeX)
    $str =~ s[ *\xA0][\xA0]g;

    # Encode unicode but skip any \, {, or } that we already encoded.
    my @parts = split(/(\$.*?\$|[\\{}_^])/, $str);
    return join('', map { /[_^{}\\\$]/ ? $_ : unicode2tex($_) } @parts);
}

sub rec {
    my ($tag, $body) = @_;

    if ($tag eq '0') { return greek($body); }
    my %attr = %{shift @$body};

    if ($tag eq 'mml:math') { return xml(@$body); }
    if ($tag eq 'mml:mi' and exists $attr{'mathvariant'} and $attr{'mathvariant'} eq 'normal')
    { return '\mathrm{' . xml(@$body) . '}' }
    if ($tag eq 'mml:mi') { return xml(@$body) }
    if ($tag eq 'mml:mo') { return xml(@$body) }
    if ($tag eq 'mml:mn') { return xml(@$body) }
    if ($tag eq 'mml:msqrt') { return '\sqrt{' . xml(@$body) . '}' }
    if ($tag eq 'mml:mrow') { return '{' . xml(@$body) . '}' }
    if ($tag eq 'mml:mspace') { return '\hspace{' . $attr{'width'} . '}' }
    if ($tag eq 'mml:msubsup') { return '{' . xml(@$body[0..1]) .
                                     '}_{' . xml(@$body[2..3]) .
                                     '}^{' . xml(@$body[4..5]) . '}' }
    if ($tag eq 'mml:msub') { return '{' . xml(@$body[0..1]) . '}_{' . xml(@$body[2..3]) . '}' }
    if ($tag eq 'mml:msup') { return '{' . xml(@$body[0..1]) . '}^{' . xml(@$body[2..3]) . '}' }
}

sub xml {
    if ($#_ == -1) { return ''; }
    elsif ($#_ == 0) { die; }
    else { rec(@_[0..1]) . xml(@_[2..$#_]); }
}

sub greek {
    my ($str) = @_;
#    370; 390
# Based on table 131 in Comprehensive Latex
    my @mapping = qw(
_ A B \Gamma \Delta E Z H \Theta I K \Lambda M N \Xi O
\Pi P _ \Sigma T \Upsilon \Phi X \Psi \Omega _ _ _ _ _ _
_ \alpha \beta \gamma \delta \varepsilon \zeta \eta \theta \iota \kappa \mu \nu \xi o
\pi \rho \varsigma \sigma \tau \upsilon \varphi \xi \psi \omega _ _ _ _ _ _);
    $str =~ s[([\N{U+0390}-\N{U+03cf}])]
             [@{[$mapping[ord($1)-0x0390] ne '_' ? $mapping[ord($1)-0x0390] : $1]}]g;
    return $str;

#    0x03b1 => '\\textgreek{a}',
#\varphi
#    0x03b2 => '\\textgreek{b}',
#    0x03b3 => '\\textgreek{g}',
#    0x03b4 => '\\textgreek{d}',
#    0x03b5 => '\\textgreek{e}',
#    0x03b6 => '\\textgreek{z}',
#    0x03b7 => '\\textgreek{h}',
#    0x03b8 => '\\textgreek{j}',
#    0x03b9 => '\\textgreek{i}',
#    0x03ba => '\\textgreek{k}',
#    0x03bb => '\\textgreek{l}',
#    0x03bc => '\\textgreek{m}',
#    0x03bd => '\\textgreek{n}',
#    0x03be => '\\textgreek{x}',
#    0x03bf => '\\textgreek{o}',
#    0x03c0 => '\\textgreek{p}',
#    0x03c1 => '\\textgreek{r}',
#    0x03c2 => '\\textgreek{c}',
#    0x03c3 => '\\textgreek{s}',
#    0x03c4 => '\\textgreek{t}',
#    0x03c5 => '\\textgreek{u}',
#    0x03c6 => '\\textgreek{f}',
#    0x03c7 => '\\textgreek{q}',
#    0x03c8 => '\\textgreek{y}',
#    0x03c9 => '\\textgreek{w}',
#
#    0x03d1 => '\\ensuremath{\\vartheta}',
#    0x03d4 => '\\textgreek{"\\ensuremath{\\Upsilon}}',
#    0x03d5 => '\\ensuremath{\\phi}',
#    0x03d6 => '\\ensuremath{\\varpi}',
#    0x03d8 => '\\textgreek{\\Koppa}',
#    0x03d9 => '\\textgreek{\\coppa}',
#    0x03da => '\\textgreek{\\Stigma}',
#    0x03db => '\\textgreek{\\stigma}',
#    0x03dc => '\\textgreek{\\Digamma}',
#    0x03dd => '\\textgreek{\\digamma}',
#    0x03df => '\\textgreek{\\koppa}',
#    0x03e0 => '\\textgreek{\\Sampi}',
#    0x03e1 => '\\textgreek{\\sampi}',
#    0x03f0 => '\\ensuremath{\\varkappa}',
#    0x03f1 => '\\ensuremath{\\varrho}',
#    0x03f4 => '\\ensuremath{\\Theta}',
#    0x03f5 => '\\ensuremath{\\epsilon}',
#    0x03f6 => '\\ensuremath{\\backepsilon}',

#ff

}

sub check {
    my ($entry, $field, $msg, $check) = @_;
    if ($entry->exists($field)) {
        $_ = $entry->get($field);
        unless (&$check()) {
            print "WARNING: $msg: ", $entry->get($field), "\n";
        }
    }
}

sub update {
    my ($entry, $field, $fun) = @_;
    if ($entry->exists($field)) {
        $_ = $entry->get($field);
        &$fun();
        if (defined $_) { $entry->set($field, $_); }
        else { $entry->delete($field); }
    }
}

sub first_name {
    my ($name) = @_;

    $name =~ s/\s\p{upper}\.$//; # Allow for a middle initial

    return
        $name =~ /^\p{upper}\p{lower}+$/ || # Simple name
        $name =~ /^\p{upper}\p{lower}+-\p{upper}\p{lower}+$/ || # Hyphenated name with upper
        $name =~ /^\p{upper}\p{lower}+-\p{lower}\p{lower}+$/ || # Hyphenated name with lower
        $name =~ /^\p{upper}\p{lower}+\p{upper}\p{lower}+$/ || # "Asian" name (e.g. XiaoLin)
        # We could allow the following but publishers often abriviate
        # names when the actual paper doesn't
        #$name =~ /^\p{upper}\.$/ || # Initial
        #$name =~ /^\p{upper}\.-\p{upper}\.$/ || # Double initial
        0;
}

sub last_name {
    my ($name) = @_;

    return
        $name =~ /^\p{upper}\p{lower}+$/ || # Simple name
        $name =~ /^\p{upper}\p{lower}+-\p{upper}\p{lower}+$/ || # Hyphenated name with upper
        $name =~ /^(O'|Mc|Mac)\p{upper}\p{lower}+$/; # Name with prefix
}

sub flatten_name {
    my @f = $_[0]->part('first');
    my @v = $_[0]->part('von');
    my @l = $_[0]->part('last');
    my @j = $_[0]->part('jr');

    @f = () unless defined $f[0];
    @v = () unless defined $v[0];
    @l = () unless defined $l[0];
    @j = () unless defined $j[0];

    return decode('utf8', join(' ', @f, @v, @l, @j));
}

sub canonical_names {
    my ($self, $entry, $field) = @_;

    my $name_format = new Text::BibTeX::NameFormat ('vljf', 0);
    $name_format->set_options(BTN_VON, 0, BTJ_SPACE, BTJ_SPACE);
    for (BTN_LAST, BTN_JR, BTN_FIRST) {
        $name_format->set_options($_, 0, BTJ_SPACE, BTJ_NOTHING);
    }
    my @names;
  NAME:
    for my $name ($entry->names($field)) {
        for my $name_group (@{$self->valid_names}) {
            for (@$name_group) {
                if (lc decode_entities(flatten_name($name)) eq lc flatten_name($_)) {
                    push @names, decode('utf8', $name_group->[0]->format($name_format));
                    next NAME;
                }
            }
        }
        print "WARNING: Suspect name: @{[$name->format($name_format)]}\n" unless
            (not defined $name->part('von') and
             not defined $name->part('jr') and
             first_name(decode_entities(decode('utf8', join(' ', $name->part('first'))))) and
             last_name(decode_entities(decode('utf8', join(' ', $name->part('last'))))));

        push @names, decode('utf8', $name->format($name_format));
    }

    # Warn about duplicate names
    my %seen;
    $seen{$_}++ and print "WARNING: Duplicate name: $_\n" for @names;

    $entry->set($field, join(' and ', @names));
}

1;
