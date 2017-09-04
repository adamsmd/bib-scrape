package Text::BibTeX::Scrape;

use warnings;
use strict;

use Algorithm::Diff;
use Encode;
use HTML::Entities qw(decode_entities);
use Text::RIS;
use Text::MetaBib;
use WWW::Mechanize;

use Text::BibTeX;
use Text::BibTeX qw(:subs);
use Text::BibTeX::Value;

my $DEBUG = 0;

sub debug {
    ($DEBUG) = @_ if @_;
    return $DEBUG;
}

my $mech;

sub scrape {
    my ($url) = @_;

    # TODO: test running without jstor_patch from home
    $mech = WWW::Mechanize->new(autocheck => 1);
    $mech->add_handler("request_send",  sub { shift->dump; return }) if $DEBUG;
    $mech->add_handler("response_done", sub { shift->dump; return }) if $DEBUG;
    $mech->agent('Mozilla/5.0');
    $mech->cookie_jar->set_cookie(0, 'MUD', 'MP', '/', 'springerlink.com', 80, 0, 0, 86400, 0);
    $mech->get($url);
    my $entry = parse($mech);
    $mech = undef;

    $entry->set('bib_scrape_url', $url);
    return $entry;
}

################

sub parse_bibtex {
    my ($bib_text) = @_;
    $bib_text =~ s/^\x{FEFF}//; # Remove Byte Order Mark

    my $entry = new Text::BibTeX::Entry;
    print "BIBTEXT:\n$bib_text\n" if $DEBUG;

    $bib_text = encode('utf8', $bib_text);

    my ($id) = $bib_text =~ m[\{(.*?),]s;
    $id =~ s[ ][_]g;
    $id =~ s[[^[:ascii:]]][?]g;
    $bib_text =~ s/\{(.*?),/{$id,/s;

    $entry->parse_s($bib_text, 0); # 1 for preserve values
    die "Can't parse BibTeX:\n$bib_text\n" unless $entry->parse_ok;

    # Parsing the bibtex converts it to utf8, so we have to decode it
    $entry->set_key(decode('utf8', $entry->key));
    for ($entry->fieldlist) { $entry->set($_, decode('utf8', $entry->get($_))) }

    return $entry;
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

sub get_url {
    my ($url) = @_;
    my $uri = URI->new_abs($url, $mech->base());
    $mech->get($uri);
    my $content = $mech->content();
    $mech->back();
    $content =~ s[<!--.*?-->][]sg; # Remove HTML comments
    $content =~ s[\s*$][]; # remove trailing whitespace
    $content =~ s[^\s*][]; # remove leading whitespace
    return $content;
}

sub get_mathml {
    my ($str) = @_;
    $str =~ s[<span\b[^>]*\bclass="mathmlsrc"[^>]*>
                <(span|a)\b[^>]*\bdata-mathURL="(.*?)"[^>]*>.*?</\1>
                .*?
                <!--(ja:math|Loading\sMathjax)-->
              </span>]
        [@{[join(" ", split(/[\r\n]+/, get_url(decode_entities($2))))]}]xg;
    return $str;
}

sub print_or_online {
    my ($entry, $field, $print, $online) = @_;
    my ($print_issn) = @$print;
    my ($online_issn) = @$online;
    if ($print_issn and $online_issn) {
        $entry->set($field, "$print_issn (Print) $online_issn (Online)");
    } elsif ($print_issn or $online_issn) {
        $entry->set($field, $print_issn || $online_issn);
    }
}

sub merge {
    my ($left, $left_split, $right, $right_split, $merge, $opts) = @_;

    my $diff = Algorithm::Diff->new(
        [grep {defined $_} (split $left_split, $left)],
        [grep {defined $_} (split $right_split, $right)], $opts);
    my $result = '';
    while ($diff->Next()) {
        $result .= &$merge(join('', $diff->Items(1)), join('', $diff->Items(2)));
    }
    return $result;
}

################

sub domain { $mech->uri()->authority() =~ m[^(|.*\.)\Q$_[0]\E]i; }

sub parse {
    for my $parse (
      *parse_acm,
      *parse_cambridge,
      *parse_computer_society,
      *parse_ieeexplore,
      *parse_ios_press,
      *parse_jstor,
      *parse_oxford_journals,
      *parse_science_direct,
      *parse_springer,
      *parse_wiley) {
      my $result = &$parse(@_);
      return $result if defined $result;
    }

    die "Unknown URI: " . $mech->uri();
}

sub parse_acm {
    domain('acm.org') || return undef;

    my ($mech) = @_;

    # BibTeX
    my ($url) = $mech->find_link(text=>'BibTeX')->url()
        =~ m[navigate\('(.*?)'];
    $mech->get($url);
    my ($i, $cont) = (1, undef);
    # Try to avoid SIGPLAN Notices, SIGSOFT Software Eng. Notes, etc.
    while ($mech->find_link(text => 'download', n => $i)) {
        $mech->follow_link(text => 'download', n => $i);
        $cont = $mech->content()
            unless defined $cont and
            $mech->content() =~ m[journal = ]i;
        $mech->back();
        $i++;
    }
    my $entry = parse_bibtex($cont);

    $mech->back();

    # Abstract
    my ($abstr_url) = $mech->content() =~ m[(tab_abstract.*?)\'];
    $mech->get($abstr_url);
    # Fix the double HTML encoding of the abstract (Bug in ACM?)
    $entry->set('abstract', decode_entities($1)) if $mech->content() =~
        m[<div style="display:inline">((?:<par>|<p>)?.+?(?:</par>|</p>)?)</div>];
    $mech->back();

    my $html = Text::MetaBib::parse($mech->content());
    $html->bibtex($entry, 'booktitle');

    # ACM gets the capitalization wrong for 'booktitle' everywhere except in the BibTeX,
    # but gets symbols right only in the non-BibTeX.  Attept to take the best of both worlds.
    $entry->set('booktitle', merge($entry->get('booktitle'), qr[\b],
                                   $html->get('citation_conference')->[0], qr[\b],
                                   sub { (lc $_[0] eq lc $_[1]) ? $_[0] : $_[1] },
                                   { keyGen => sub { lc shift }})) if $entry->exists('booktitle');

    $entry->set('title', $mech->content() =~
                m[<h1 class="mediumb-text".*?><strong>(.*?)</strong></h1>])
        if $entry->exists('title');

    return $entry;
}

sub parse_cambridge {
    domain('cambridge.org') || return undef;

    my ($mech) = @_;

    $mech->content() =~ m[data-prod-id="([0-9A-F]+)">Export citation</a>];
    my $product_id = $1;
    $mech->get("https://www.cambridge.org/core/services/aop-easybib/export/?exportType=bibtex&productIds=$product_id&citationStyle=bibtex");
    my $entry = parse_bibtex($mech->content());
    $mech->back();

    my ($abst) = $mech->content() =~ m[<div class="abstract" data-abstract-type="normal">(.*?)</div>]s;
    $abst =~ s[^<title>Abstract</title>][] if $abst;
    $abst =~ s/\n+/\n/g if $abst;
    $entry->set('abstract', $abst) if $abst;

    my $html = Text::MetaBib::parse($mech->content());

    $entry->set('title', @{$html->get('citation_title')});

    my ($month) = (join(' ',@{$html->get('citation_publication_date')}) =~ m[^\d\d\d\d/(\d\d)]);
    $entry->set('month', $month);

    my ($doi) = join(' ', @{$html->get('citation_pdf_url')}) =~ m[/(S\d{16})a\.pdf];
    $entry->set('doi', "10.1017/$doi");

    print_or_online($entry, 'issn', [$html->get('citation_issn')->[0]], [$html->get('citation_issn')->[1]]);

    return $entry;
}

sub parse_computer_society {
    domain('computer.org') || return undef;

    my ($mech) = @_;

    my $html = Text::MetaBib::parse(decode('utf8', $mech->content()));
    my $entry = parse_bibtex("\@" . ($html->type() || 'misc') . "{unknown_key,}");

    $mech->follow_link(text => 'BibTex');
    my $bib_text = $mech->content();
    $bib_text =~ s[<br/>][\n]g;
    my $f = parse_bibtex(decode('utf8', $bib_text));
    $mech->back();

    if ($entry->type() eq 'inproceedings') { # IEEE gets this all wrong
        $entry->set('series', $f->get('journal')) if $f->exists('journal');
        $entry->delete('journal');
    }
    $entry->set('address', $f->get('address')) if $f->exists('address');
    $entry->set('volume', $f->get('volume')) if $f->exists('volume');
    update($entry, 'volume', sub { $_ = undef if $_ eq "00" });

    $html->bibtex($entry);

    # Don't use the MetaBib for this as IEEE doesn't escape quotes property
    $entry->set('abstract', $mech->content() =~ m[<div class="abstractText abstractTextMB">(.*?)</div>]);

    return $entry;
}

# IEEE is evil because they require a subscription just to get bibliography data
# (they also use JavaScript to implement simple links)
sub parse_ieeexplore {
    domain('ieeexplore.ieee.org') || return undef;

    my ($mech, $fields) = @_;
    my ($record) = $mech->content() =~ m[var recordId = "(\d+)";];

    my $html = Text::MetaBib::parse($mech->content());
    # Ick, work around javascript by hard coding the URL
    $mech->get("http://ieeexplore.ieee.org/xpl/downloadCitations?".
               "recordIds=$record&".
               "fromPage=&".
               "citations-format=citation-abstract&".
               "download-format=download-bibtex");
    my $cont = $mech->content();
    $cont =~ s/<br>//gi;
    my $entry = parse_bibtex($cont);
    $mech->back();

    $html->bibtex($entry);
    return $entry
}

sub parse_ios_press {
    domain('iospress.com') || return undef;

    my ($mech) = @_;

    my $html = Text::MetaBib::parse($mech->content());
    $mech->follow_link(text => 'RIS');
    my $f = Text::RIS::parse(decode('utf8', $mech->content()))->bibtex();
    my $entry = parse_bibtex("\@" . $f->type . " {unknown_key,}");
    # TODO: missing items?
    for ('journal', 'title', 'volume', 'number', 'abstract', 'pages',
         'author', 'year', 'month', 'doi') {
        $entry->set($_, $f->get($_)) if $f->exists($_);
    }
    $mech->back();

    my ($pub) = ($mech->content() =~ m[>Publisher</td><td.*?>(.*?)</td>]i);
    $entry->set('publisher', $pub) if defined $pub;

    my ($issn) = ($mech->content() =~ m[>ISSN</td><td.*?>(.*?)</td>]i);
    $issn =~ s[<br/?>][ ];
    $entry->set('issn', $issn) if defined $issn;

    my ($abstract) = ($mech->content() =~ m[<div class="abstract">\s*<p>(.*?)</p>\s*</div>]i);
    $entry->set('abstract', $abstract) if defined $abstract;

    $html->bibtex($entry);
    return $entry;
}

sub parse_jstor {
    domain('jstor.org') || return undef;

    my ($mech) = @_;
    my $html = Text::MetaBib::parse($mech->content());

    $mech->follow_link(text_regex => qr[Cite this Item]);
    $mech->follow_link(text => 'Export a Text file');

    my $cont = $mech->content();
    my $entry = parse_bibtex($cont);
    $mech->back();

    $mech->find_link(text => 'Export a RIS file');
    $mech->follow_link(text => 'Export a RIS file');
    my $f = Text::RIS::parse(decode('utf8', $mech->content()))->bibtex();
    $entry->set('month', $f->get('month'));
    $mech->back();

    $mech->back();

    my ($doi) = $mech->content() =~ m[<div class="doi">(.*?)</div>]s;
    $entry->set('doi', $doi) if defined $doi;

    $html->bibtex($entry);

    my ($abs) = $mech->content() =~ m[<div class="abstract1"[^>]*>(.*?)</div>]s;
    $entry->set('abstract', $abs) if defined $abs;

    return $entry;
}

sub parse_oxford_journals {
    domain('oup.com') || return undef;

    my ($mech) = @_;

    my $html = Text::MetaBib::parse($mech->content());
    my $entry = parse_bibtex("\@article{unknown_key,}");
    $html->bibtex($entry);

    my ($abstract) = ($mech->content() =~ m[<section class="abstract">\s*(.*?)\s*</section>]si);
    $entry->set('abstract', $abstract) if defined $abstract;

    print_or_online($entry, 'issn',
         [$mech->content() =~ m[Print ISSN (\d\d\d\d-\d\d\d[0-9X])]],
         [$mech->content() =~ m[Online ISSN (\d\d\d\d-\d\d\d[0-9X])]]);

    my ($title) = $mech->content =~ m[<h1 id="article-title-1" itemprop="headline">\s*(.*?)\s</h1>]si;
    $entry->set('title', $title) if defined $title;

    return $entry;
}

sub parse_science_direct {
    domain('sciencedirect.com') || domain('elsevier.com') || return undef;

    my ($mech) = @_;

    # Evil Elsiver uses JavaScript to redirect
    my ($redirect) = $mech->content() =~ m[<input type="hidden" name="redirectURL" value="([^"]*?)" id="redirectURL"/>];
    if (defined $redirect) {
        $redirect =~ s[\%([0-9A-Z]{2})][@{[chr(hex $1)]}]ig; # URL decode
        $mech->get($redirect);
    }

    my $html = Text::MetaBib::parse($mech->content());

    # Evil Science Direct uses JavaScript to create links
    my ($pii) = $mech->content() =~ m["sd:article:pii:(s?\d{15}(\d|x))"];

    $mech->get("https://www.sciencedirect.com/sdfe/arp/cite?pii=$pii&format=text%2Fx-bibtex&withabstract=true");
    my $entry = parse_bibtex($mech->content());
    $mech->back();

    my ($title) = $mech->content() =~ m[<h1 class="article-title" [^>]*>(.*?)</h1>]s;
    $title =~ s[<a\b[^>]*>(.*?)</a>][]s;
    $entry->set('title', $title);

    my ($keywords) = $mech->content() =~ m[>Keywords</h2>(<div\b[^>]*>.*?</div>)</div>]s;
    if (defined $keywords) {
        $keywords =~ s[<div\b[^>]*?>(.*?)</div>][$1; ]sg;
        $keywords =~ s[; $][];
        $entry->set('keywords', $keywords);
    }

    my ($abst) = $mech->content() =~ m[<div class="abstract author"[^>]*>(.*?</div>)</div>];
    $abst = "" unless defined $abst;
    $abst =~ s[<h2\b[^>]*>Abstract</h2>][]g;
    $abst =~ s[<div\b[^>]*>(.*)</div>][$1]s;
    $entry->set('abstract', get_mathml($abst));

    if ($entry->exists('note') and $entry->get('note') ne '') {
        $entry->set('series', $entry->get('note'));
        $entry->delete('note');
    }

    my ($iss_first) = $mech->content() =~ m["iss-first":"(\d+)"];
    my ($iss_last) = $mech->content() =~ m["iss-last":"(\d+)"];
    $entry->set('number', defined $iss_last ? "$iss_first--$iss_last" : "$iss_first");

    $mech->get("http://www.sciencedirect.com/sdfe/arp/cite?pii=$pii&format=application%2Fx-research-info-systems&withabstract=false");
    my $f = Text::RIS::parse(decode('utf8', $mech->content()))->bibtex();
    $entry->set('month', $f->get('month'));
    $mech->back();

# TODO: editor

    $html->bibtex($entry);

    return $entry;
}

sub parse_springer {
    domain('springer.com') || return undef;

    my ($mech) = @_;
# TODO: handle books
    $mech->follow_link(url_regex => qr[format=bibtex]);
    my $entry_text = $mech->content();
    $entry_text =~ s[^(\@.*\{)$][$1X,]m; # Fix invalid BibTeX (missing key)
    my $entry = parse_bibtex(decode('utf8', $entry_text));
    $mech->back();
    $mech->back();

    my ($abstr) = join('', $mech->content() =~ m[>(?:Abstract|Summary)</h2>(.*?)</section]s);
    $entry->set('abstract', $abstr) if defined $abstr;

    my $html = Text::MetaBib::parse($mech->content());
    my ($year, $month, $day) = $mech->content() =~ m["abstract-about-cover-date">(\d\d\d\d)-(\d\d)-(\d\d)</dd>];
    $entry->set('month', $month) if defined $month;

    print_or_online($entry, 'issn',
        [$mech->content() =~ m[setTargeting\("pissn","(\d\d\d\d-\d\d\d[0-9X])"\)]],
        [$mech->content() =~ m[setTargeting\("eissn","(\d\d\d\d-\d\d\d[0-9X])"\)]]);

    my @editors = $mech->content() =~ m[<li itemprop="editor"[^>]*>\s*<a[^>]*>(.*?)</a>]sg;
    $entry->set('editor', join(' and ', @editors)) if @editors;

    print_or_online($entry, 'isbn',
        [$mech->content() =~ m[id="print-isbn">(.*?)</span>]],
        [$mech->content() =~ m[id="electronic-isbn">(.*?)</span>]]);

    my ($link) = $mech->find_link(text => 'About this book');
    if (defined $link) {
      $mech->follow_link(text => 'About this book');

      my ($series) = $mech->content() =~ m[<dt>Series Title</dt>\s*<dd>(.*?)</dd>];
      $entry->set('series', $series) if defined $series;

      my ($volume) = $mech->content() =~ m[<dt>Series Volume</dt>\s*<dd>(.*?)</dd>];
      $entry->set('volume', $1) if defined $volume;
    }

    $entry->set('keywords', $1) if $mech->content() =~ m[<div class="KeywordGroup" lang="en">(?:<h3 class="Heading">KeyWords</h3>)?(.*?)</div>];
    update($entry, 'keywords', sub {
      s[^<span class="Keyword">\s*(.*?)\s*</span>$][$1];
      s[\s*</span><span class="Keyword">\s*][; ]g;
          });

    $html->bibtex($entry, 'month');

    # The publisher field should not include the address
    update($entry, 'publisher', sub { $_ = 'Springer' if $_ eq ('Springer, ' . ($entry->get('address') // '')) });

    return $entry;
}

sub parse_wiley {
    domain('wiley.com') || return undef;

    my ($mech) = @_;
    $mech->follow_link(url_regex => qr[/abstract]) if $mech->find_link(url_regex => qr[/abstract]);
    $mech->follow_link(text => 'Export Citation for this Article');
    $mech->submit_form(with_fields => {
        'fileFormat' => 'BIBTEX', 'hasAbstract' => 'CITATION_AND_ABSTRACT'});
    my $entry = parse_bibtex(decode('utf8', $mech->content()));
    $mech->back(); $mech->back();

    my $html = Text::MetaBib::parse($mech->content());

    # Ugh! Both the BibTeX and the HTML have problems.  Here we try to
    # pick out the best from each.  The HTML is usually better except that
    # it uses <img> takes for some math.
    my $bibtex_abstr = $entry->get('abstract');
    my ($html_abstr) = ($mech->content() =~ m[<div id="abstract"><h3>Abstract</h3>(<div class="para">.*?</div>)</div>]);
    my $math_img = qr[<img [^>]*?>]; # We could use a more complicated regex, but this is good enough

    # Try to find the diff between the BibTeX and HTML
    $entry->set('abstract', merge(
                    $entry->get('abstract'),
                    qr[(\$.*?\$|\\documentclass.*?\\end\{document\})?],
                    $mech->content() =~ m[<div id="abstract"><h3>Abstract</h3>(<div class="para">.*?</div>)</div>],
                    qr[(\&[^;]*?;|$math_img|<span[^>]*?>$math_img</span>)?],
                    sub { my ($bib, $html) = @_;
                          $html =~ s[([{}])][\\$1]g; # Escape the HTML while we know it is still HTML
                          if ($html =~ m[$math_img]) {
                              # Replace images (and special characters surrounding it) with BibTeX.
                              # (By substituting we keep around things like </em> at the start or <em> at the end
                              $html =~ s[(\&[^;]*?;)*($math_img|<span[^>]*?>$math_img</span[^>]*?>)(\&[^;]*?;)*][$bib]is;
                          }
                          $html;
                    }, {}));

    # Finally, we clean up the abstract
    update($entry, 'abstract', sub { s[\\documentclass\{article\} \\usepackage\{mathrsfs\} \\usepackage\{amsmath,amssymb,amsfonts\} \\pagestyle\{empty\} \\begin\{document\} \\begin\{align\*\}(.*?)\\end\{align\*\} \\end\{document\}][\\ensuremath{$1}]isg; });
    update($entry, 'abstract', sub { s[<div class="para">(.*?)</div>][\n\n$1\n\n]isg });
    update($entry, 'abstract',
           sub { s[(Copyright )?(.|&copy;) \d\d\d\d John Wiley (.|&amp;) Sons, (Ltd|Inc)\.\s*][] });
    update($entry, 'abstract',
           sub { s[(.|&copy;) \d\d\d\d Wiley Periodicals, Inc\. Random Struct\. Alg\..*, \d\d\d\d][] });

    $html->bibtex($entry, 'title');

    # To handle multiple month issues we must use HTML
    my ($month) = ($mech->content() =~ m[<span id="issueDate">((\w|\/)*) \d*</span>]);
    $entry->set('month', $month) if $month;

    # Choose the title either from bibtex or HTML based on whether we thing the BibTeX has the proper math in it.
    $entry->set('title', $mech->content() =~ m[<h1 class="articleTitle">(.*?)</h1>]s)
        unless $entry->get('title') =~ /\$/;


    return $entry;
}

1;
