package Text::BibTeX::Fix;

use warnings;
use strict;

use Carp;

use Encode;
use HTML::Entities qw(decode_entities);
use Scalar::Util qw(blessed);
use TeX::Unicode;
use Text::ISBN;
use XML::Parser;

use Text::BibTeX;
use Text::BibTeX qw(:subs :nameparts :joinmethods);
use Text::BibTeX::Value;
use Text::BibTeX::Fix;
use Text::ISBN;
use TeX::Unicode;
use HTML::Entities;
use Encode;

use Text::BibTeX::Months;
use Text::BibTeX::Name;
use Text::BibTeX::NameFormat;

use Getopt::Long qw(:config auto_version auto_help);

use XML::Twig;
use Scalar::Util qw(blessed);

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
  debug => '$', generate_key => '$', final_comma => '$',
  escape_acronyms => '$', isbn13 => '$', isbn_sep => '$',
  no_encode => '%', no_collapse => '%', omit => '%', omit_empty => '%',
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
      edition month year issue_date jstor_formatteddate
      organization publisher address
      language isbn issn doi eid acmid url eprint bib_scrape_url
      note annote keywords abstract copyright));
    array_flag($cfg, \%options, 'valid_names', qw());

    scalar_flag($cfg, \%options, 'debug', 0);
    scalar_flag($cfg, \%options, 'generate_key', 1);
    scalar_flag($cfg, \%options, 'final_comma', 1);
    scalar_flag($cfg, \%options, 'escape_acronyms', 1);
    scalar_flag($cfg, \%options, 'isbn13', 0);
    scalar_flag($cfg, \%options, 'isbn_sep', '-');

    hash_flag($cfg, \%options, 'no_encode', qw(doi url eprint bib_scrape_url));
    hash_flag($cfg, \%options, 'no_collapse', qw());
    hash_flag($cfg, \%options, 'omit', qw());
    hash_flag($cfg, \%options, 'omit_empty', qw(abstract issn doi));

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
        ($entry->get('url') || "") =~ m[^http://dx.doi.org/.*$]);
    update($entry, 'doi', sub { s[http://[^/]+/][]i; s[DOI:\s*][]ig; });

    # Page numbers: no "pp." or "p."
    # TODO: page fields
    # [][pages][pp?\.\s*][]ig;
    update($entry, 'pages', sub { s[pp?\.\s*][]ig; });

    # [][number]rename[issue][.+][$1]delete;
    # rename fields
    for (['issue', 'number'], ['keyword', 'keywords']) {
        # Fix broken field names (SpringerLink and ACM violate this)
        if ($entry->exists($_->[0]) and not $entry->exists($_->[1])) {
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
    }

    update($entry, 'isbn', sub { $_ = Text::ISBN::canonical($_, $self->isbn13, $self->isbn_sep) });
    # TODO: ISSN: Print vs electronic vs native, dash vs no-dash vs native
    # TODO: Keywords: ';' vs ','

    # TODO: Author, Editor, Affiliation: List of renames
# Booktitle, Journal, Publisher*, Series, School, Institution, Location*, Edition*, Organization*, Publisher*, Address*, Language*:
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
#
#    }

    # Don't include pointless URLs to publisher's page
    # [][url][http://dx.doi.org/][];
    # TODO: via Omit if matches
    # TODO: omit if ...
    update($entry, 'url', sub {
        $_ = undef if m[^(http://dx.doi.org/
                         |http://doi.acm.org/
                         |http://portal.acm.org/citation.cfm
                         |http://www.jstor.org/stable/
                         |http://www.sciencedirect.com/science/article/)]x; } );
    # TODO: via omit if empty
    update($entry, 'note', sub { $_ = undef if $_ eq "" });
    # TODO: add $doi to omit if matches
    # [][note][$doi][]
    # regex delete if looks like doi
    # Fix Springer's use of 'note' to store 'doi'
    update($entry, 'note', sub { $_ = undef if $_ eq ($entry->get('doi') or "") });

    # Eliminate Unicode but not for doi and url fields (assuming \usepackage{url})
    for my $field ($entry->fieldlist()) {
        warn "Undefined $field" unless defined $entry->get($field);
        $entry->set($field, latex_encode($entry->get($field)))
            unless exists $self->no_encode->{$field};
    }

    # Collapse spaces and newlines
    $self->no_collapse->{$_} or update($entry, $_, sub {
        s[\s*$][]; # remove trailing whitespace
        s[^\s*][]; # remove leading whitespace
        s[\n{2,} *][{\\par}]sg; # BibTeX eats whitespace so convert "\n\n" to paragraph break
        s[\s*\n\s*][ ]sg; # Remove extra line breaks
        s[{\\par}][\n{\\par}\n]sg; # Nicely format paragraph breaks
        #s[\s{2,}][ ]sg; # Remove duplicate whitespace
                                       }) for $entry->fieldlist();

    # TODO: Title Capticalization: Initialisms, After colon, list of proper names
    update($entry, 'title', sub { s/((\d*[[:upper:]]\d*){2,})/{$1}/g; }) if $self->escape_acronyms;

    # Generate an entry key
    # TODO: Formats: author/editor1.last year title/journal.abbriv
    # TODO: Remove doi?
    if ($self->generate_key or not defined $entry->key()) {
        my ($name) = ($entry->names('author'), $entry->names('editor'));
        #$organization, or key
        if ($name and $entry->exists('year')) {
            ($name) = purify_string(join("", $name->part('last')));
            $entry->set_key($name . ':' . $entry->get('year') .
                            ($entry->exists('doi') ? ":" . $entry->get('doi') : ""));
        }
    }

    # Use bibtex month macros
    update($entry, 'month', # Must be after field encoding
           sub { my @x = split qr[\b];
                 for (1..$#x) {
                     $x[$_] = "" if $x[$_] eq "." and str2month(lc $x[$_-1]);
                 }
                 $_ = new Text::BibTeX::Value(
                     map { (str2month(lc $_)) or ([Text::BibTeX::BTAST_STRING, $_]) }
                     map { $_ ne "" ? $_ : () } @x)});


    # Omit fields we don't want
    # TODO: controled per type or with other fields or regex matching
    $entry->exists($_) and $entry->delete($_) for (keys %{$self->omit});
    $entry->exists($_) and $entry->get($_) eq '' and $entry->delete($_) for (keys %{$self->omit_empty});

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
    $str =~ s[<a [^>]*onclick="toggleTabs\(.*?\)">.*?</a>][]isg; # Science Direct

    # HTML formatting
    $str =~ s[<a( .*?)?>(.*?)</a>][$2]isog; # Remove <a> links
    $str =~ s[<p(| [^>]*)>(.*?)</p>][$2\n\n]isg; # Replace <p> with "\n\n"
    $str =~ s[<par(| [^>]*)>(.*?)</par>][$2\n\n]isg; # Replace <par> with "\n\n"
    $str =~ s[<span style="font-family:monospace">(.*?)</span>][\\texttt{$1}]i; # Replace monospace spans with \texttt
    $str =~ s[<span( .*?)?>(.*?)</span>][$2]isg; # Remove <span>
    $str =~ s[<span( .*?)?>(.*?)</span>][$2]isg; # Remove <span>
    $str =~ s[<i>(.*?)</i>][\\textit{$1}]isog; # Replace <i> with \textit
    $str =~ s[<italic>(.*?)</italic>][\\textit{$1}]isog; # Replace <italic> with \textit
    $str =~ s[<em>(.*?)</em>][\\emph{$1}]isog; # Replace <em> with \emph
    $str =~ s[<strong>(.*?)</strong>][\\textbf{$1}]isog; # Replace <strong> with \textbf
    $str =~ s[<b>(.*?)</b>][\\textbf{$1}]isog; # Replace <b> with \textbf
    $str =~ s[<small>(.*?)</small>][{\\small $1}]isog; # Replace <small> with \small
    $str =~ s[<sup>(.*?)</sup>][\\textsuperscript{$1}]isog; # Super scripts
    $str =~ s[<supscrpt>(.*?)</supscrpt>][\\textsuperscript{$1}]isog; # Super scripts
    $str =~ s[<sub>(.*?)</sub>][\\textsubscript{$1}]isog; # Sub scripts

    $str =~ s[<img src="http://www.sciencedirect.com/scidirimg/entities/([0-9a-f]+).gif".*?>][@{[chr(hex $1)]}]isg; # Fix for Science Direct
    #$str =~ s[<!--title-->$][]isg; # Fix for Science Direct

    # MathML formatting
    my $math_str; # Using this variable is icky but I can't figure out how to eliminate the root of the xml
sub xml {
    my $x = $_;
#    print join(":", @_), "\n";
#    $x->replace_with(map { blessed $_ ? $_->copy() : XML::Twig::Elt->new('#PCDATA' => $_) } @_);
    join('', map { blessed $_ ? rec($_) : greek($_) } @_);
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

sub rec {
    my ($x) = @_;
    if ($x->tag eq 'mml:math') { return xml($x->children()); }
    if ($x->tag eq 'mml:mi' and defined $x->att('mathvariant') and $x->att('mathvariant') eq 'normal')
    { return xml('\mathrm{', $x->children(), '}') }
    if ($x->tag eq 'mml:mi') { return xml($x->children()) }
    if ($x->tag eq 'mml:mo') { return xml($x->children()) }
    if ($x->tag eq 'mml:mn') { return xml($x->children()) }
    if ($x->tag eq 'mml:msqrt') { return xml('\sqrt{', $x->children(), '}') }
    if ($x->tag eq 'mml:mrow') { return xml('{', $x->children(), '}') }
    if ($x->tag eq 'mml:mspace') { return xml('\hspace{', $x->att('width'), '}') }
    if ($x->tag eq 'mml:msubsup') { return xml('{', $x->child(0), '}_{', $x->child(1), '}^{', $x->child(2), '}') }
    if ($x->tag eq 'mml:msub') { return xml('{', $x->child(0), '}_{', $x->child(1), '}') }
    if ($x->tag eq 'mml:msup') { return xml('{', $x->child(0), '}^{', $x->child(1), '}') }
    if ($x->tag eq '#PCDATA') { return greek($x->sprint) }
}

#print "[$str]\n";
    my $twig = XML::Twig->new();
    $str =~ s[(<mml:math\b[^>]*>.*?</mml:math>)][\\ensuremath{@{[rec($twig->parse($1)->root)]}}]gs; # TODO: ensuremath (but avoid latex encoding)

    # Misc fixes
    my @parts = split(/(\$.*?\$|[\\{}_^])/, $str);
    $str = join('', map { /[_^{}\\\$]/ ? $_ : unicode2tex($_) } @parts);
    #$str =~ s[([^{}\\]+)][@{[unicode2tex($1)]}]g; # Encode unicode but skip any \, {, or } that we already encoded.
    return $str;
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
          VALID_NAME:
            for my $_ (@$name_group) {
                for my $part (qw(von last jr first)) {
                    if (lc decode('utf8', join(' ', $name->part($part))) ne
                        lc decode('utf8', join(' ', $_->part($part)))) {
                        next VALID_NAME;
                    }
                }
                push @names, decode('utf8', $name_group->[0]->format($name_format));
                next NAME;
            }
        }
        print "WARNING: Unrecognized name @{[$name->format($name_format)]}\n";
        push @names, decode('utf8', $name->format($name_format));
    }

    $entry->set($field, join(' and ', @names));
}

1;
