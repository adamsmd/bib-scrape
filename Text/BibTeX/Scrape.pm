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
    $entry->parse_s(encode('utf8', $bib_text), 0); # 1 for preserve values
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

################

sub domain { $mech->uri()->authority() =~ m[^(|.*\.)\Q$_[0]\E]i; }

sub parse {
    if (domain('acm.org')) { parse_acm(@_); }
    elsif (domain('sciencedirect.com')) { parse_science_direct(@_); }
    elsif (domain('link.springer.com')) { parse_springerlink(@_); }
    elsif (domain('journals.cambridge.org')) { parse_cambridge_university_press(@_); }
    elsif (domain('computer.org')) { parse_ieee_computer_society(@_); }
    elsif (domain('jstor.org')) { parse_jstor(@_); }
    elsif (domain('iospress.metapress.com')) { parse_ios_press(@_); }
    elsif (domain('ieeexplore.ieee.org')) { parse_ieeexplore(@_); }
    elsif (domain('onlinelibrary.wiley.com')) {parse_wiley(@_); }
    elsif (domain('oxfordjournals.org')) { parse_oxford_journals(@_); }
    else { die "Unknown URI: " . $mech->uri(); }
}

sub parse_acm {
    my ($mech) = @_;

    # BibTeX
    my ($url) = $mech->find_link(text=>'BibTeX')->url()
        =~ m[navigate\('(.*?)'];
    $mech->get($url);
    my ($i, $cont) = (1, undef);
    # Try to avoid SIGPLAN Notices
    while ($mech->find_link(text => 'download', n => $i)) {
        $mech->follow_link(text => 'download', n => $i);
        $cont = $mech->content()
            unless defined $cont and
            $mech->content() =~ m[journal = \{?SIGPLAN Not]i;
        $mech->back();
        $i++;
    }
    $cont =~ s[(\@.*) ][$1]; # Prevent keys with spaces
    my $entry = parse_bibtex($cont);

    $mech->back();

    # Un-abbreviated journal title, but avoid spurious "journal" when
    # proceedings are published in SIGPLAN Not.
    my $html = Text::MetaBib::parse($mech->content());
    $entry->set('journal', $html->get('citation_journal_title')->[0]) if $entry->exists('journal');

    $entry->set('author', $html->authors()) if $entry->exists('author');

    $entry->set('title', $mech->content() =~
                m[<h1 class="mediumb-text".*?><strong>(.*?)</strong></h1>])
        if $entry->exists('title');

    # ACM gets the capitalization wrong for 'booktitle' everywhere except in the BibTeX,
    # but gets symbols right only in the non-BibTeX.  Attept to take the best of both worlds.
    if ($entry->exists('booktitle')) {
        my $diff = Algorithm::Diff->new(
            [split m[\b], $entry->get('booktitle')],
            [split m[\b], $html->get('citation_conference')->[0]],
            { keyGen => sub { lc shift } } );
        my $booktitle = '';
        while ($diff->Next()) {
            my $bibtex = join('', $diff->Items(1));
            my $html = join('', $diff->Items(2));
            $booktitle .= (lc $bibtex eq lc $html) ? $bibtex : $html;
        }
        $entry->set('booktitle', $booktitle);
    }

    # Abstract
    my ($abstr_url) = $mech->content() =~ m[(tab_abstract.*?)\'];
    $mech->get($abstr_url);
    if (my ($abstr) = $mech->content() =~
        m[<div style="display:inline">((?:<par>|<p>)?.+?(?:</par>|</p>)?)</div>]) {
        # Fix the double HTML encoding of the abstract (Bug in ACM?)
        $entry->set('abstract', decode_entities($abstr));
    }

    return $entry;
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

sub parse_science_direct {
    my ($mech) = @_;

    # Find the title and reverse engineer the Unicode
    $mech->follow_link(text => "Screen reader users, click here to load entire article");

    my ($title) = $mech->content() =~ m[<h1 class="svTitle".*?>\s*(.*?)\s*</h1>]s;
    my ($keywords) = $mech->content() =~ m[<ul class="keyword".*?>\s*(.*?)\s*</ul>]s;
    $keywords = "" unless defined $keywords;
    $keywords =~ s[<li.*?>(.*?)</li>][$1]sg;
    $keywords = get_mathml($keywords);

    $title =~ s[<sup><a\b[^>]*\bclass="intra_ref"[^>]*>.*?</a></sup>][];
    $title = get_mathml($title);
    my ($abst) = $mech->content() =~ m[<div class="abstract svAbstract *".*?>\s*(.*?)\s*</div>];
    $abst = "" unless defined $abst;
    $abst =~ s[<h2 class="secHeading".*?>Abstract</h2>][]g;
    $abst = get_mathml($abst);

    my ($series) = $mech->content() =~ m[<p class="specIssueTitle">(.*?)</p>];

    $mech->submit_form(with_fields => {
        'format' => 'cite', 'citation-type' => 'BIBTEX'});
    my $entry = parse_bibtex($mech->content());
    $entry->set('title', $title);
    $entry->set('abstract', $abst);
    $entry->delete('keywords'); # Clear 'keywords' duplication that breaks Text::BibTeX
    $entry->set('keywords', $keywords) if $keywords ne '';
    $entry->set('series', $series) if defined $series and $series ne '';
    $mech->back();

    $mech->submit_form(with_fields => {
        'format' => 'cite-abs', 'citation-type' => 'RIS'});
    my $f = Text::RIS::parse(decode('utf8', $mech->content()))->bibtex();
    $entry->set('month', $f->get('month'));
    $entry->delete('note') if $f->exists('booktitle') and $f->get('booktitle') eq $entry->get('note');
    $entry->set('series', $f->get('booktitle')) if !$entry->exists('series') and $f->exists('booktitle');

# TODO: editor

    return $entry;
}

sub parse_springerlink {
    my ($mech) = @_;
# TODO: handle books
    $mech->follow_link(url_regex => qr[/export-citation/]);

    $mech->follow_link(url_regex => qr[/export-citation/.+\.bib]);
    my $entry_text = $mech->content();
    $entry_text =~ s[^(\@.*\{)$][$1X,]m; # Fix invalid BibTeX (missing key)
    my $entry = parse_bibtex(decode('utf8', $entry_text));
    $mech->back();

    $mech->follow_link(url_regex => qr[/export-citation/.+\.enw]);
    my $f = Text::RIS::parse($mech->content())->bibtex();
    ($f->exists($_) && $entry->set($_, $f->get($_))) for ('doi', 'month', 'issn', 'isbn');
    $mech->back();
    $mech->back();

    my ($abstr) = join('', $mech->content =~ m[<div class="abstract-content formatted".*?>(.*?)</div>]sg);
    $entry->set('abstract', $abstr) if defined $abstr;

    my ($keywords) = $mech->content =~
        m[<p\b[^>]*?class="Keyword"><span\b[^>]*?class="KeywordHeading">.*?</span>(.*?)</p>]sg;
    $entry->set('keyword', join('; ', split('&nbsp;-&nbsp;', $keywords))) if defined $keywords;

    my ($affiliations) = $mech->content =~ m[<ul class="author-affiliations">(.*?)</ul>]s;
    my @affiliations = $affiliations =~ m[<span class="affiliation">(.*?)</span>]sg;
    $affiliations = join('', @affiliations);
    $affiliations =~ s/,\s*$//mg;
    $entry->set('affiliation', $affiliations) if @affiliations;

    my $html = Text::MetaBib::parse($mech->content());
    $entry->set('journal', $html->get('citation_journal_title')->[0]) if $entry->exists('journal');
    $entry->set('author', $html->authors()) if $entry->exists('author');
    my ($year, $month, $day) = $mech->content =~ m["abstract-about-cover-date">(\d\d\d\d)-(\d\d)-(\d\d)</dd>];
    $entry->set('month', $month) if defined $month;

    issn($entry,
         [$mech->content() =~ m[setTargeting\("pissn","(\d\d\d\d-\d\d\d[0-9X])"\)]],
         [$mech->content() =~ m[setTargeting\("eissn","(\d\d\d\d-\d\d\d[0-9X])"\)]]);

    my @editors = $mech->content() =~ m[<li itemprop="editor"[^>]*>\s*<a[^>]*>(.*?)</a>]sg;
    $entry->set('editor', join(' and ', @editors)) if @editors;

    return $entry;
}

sub parse_cambridge_university_press {
    my ($mech) = @_;

    $mech->follow_link(text => 'Abstract') if defined $mech->find_link(text => 'Abstract');
    $mech->follow_link(text => 'Export Citation');
    $mech->submit_form(form_name => 'exportCitationForm',
                       fields => {'Download' => 'Download',
                                  'displayAbstract' => 'Yes',
                                  'format' => 'BibTex'});
    my $entry = parse_bibtex($mech->content());
    update($entry, 'abstract', sub { s/^\s*ABSTRACT\s*//; });
    $mech->back(); $mech->back();

    my ($abst) = $mech->content() =~ m[>Abstract</.*?><p>(<p>.*?</p>)\s*</p>]s;
    $abst =~ s/\n+/\n/g if $abst;
    $entry->set('abstract', $abst) if $abst;

    $entry->set('title',
                join(": ",
                     map { $_ ne "" ? $_ : () }
                     ($mech->content() =~ m[<h2><font.*?>(.*?)</font></h2>]sg,
                      $mech->content() =~ m[</h3>\s*<h3>(.*?)(?=</h3>)]sg
                     )));
    $entry->set('title', $mech->content() =~
                m[<div id="codeDisplayWrapper">\s*<div.*?>\s*<div.*?>(.*?)</div>]s)
        unless $entry->get('title');

    my $html = Text::MetaBib::parse($mech->content());
    if ($html->exists('citation_publication_date') and join('',@{$html->get('citation_publication_date')}) =~ m[.]) {
        my ($year, $month) = $html->date('citation_publication_date');
        $entry->set('month', $month);
    }

    my ($doi) = join(' ', @{$html->get('citation_pdf_url')}) =~ m[^http://journals.cambridge.org/article_(S\d{16})$];
    update($entry, 'doi', sub { $_ = "10.1017/$doi" if defined $doi });

    update($entry, 'abstract', sub { $_ = undef if m[^\s*$] });
    update($entry, 'doi', sub { $_ = undef if $_ eq "null" });
    update($entry, 'author', sub { $_ = undef if $_ eq "" });
    update($entry, 'url', sub { $_ = undef if $_ eq join(' ',@{$html->get('citation_pdf_url')})});

    return $entry;
    # TODO: fix case of authors
}

sub parse_ieee_computer_society {
    my ($mech) = @_;

    my $html = Text::MetaBib::parse(decode('utf8', $mech->content()));
    my $entry = parse_bibtex("\@" . ($html->type() || 'misc') . "{unknown_key,}");

    $html->exists($_->[0]) and $entry->set($_->[1], join(' ; ', @{$html->get($_->[0])})) for (
#      editor affiliation title
        ['citation_title', 'title'],
#      howpublished booktitle journal volume number series
        ['citation_conference', 'booktitle'],
        ['citation_journal_title', 'journal'], ['citation_volume', 'volume'],
        ['citation_issue', 'number'], # patent_number, technical_report_number
#      type school institution location
#      chapter pages
#      edition month year
#      organization publisher address
        ['dc.publisher', 'publisher'],
#      language isbn issn doi url
        ['dc.language', 'language'],
        ['citation_isbn', 'isbn'], ['citation_issn', 'issn'], ['citation_doi', 'doi'],
#        ['citation_mjid', 'mjid'],
#        ['citation_pdf_url', 'pdf_url'],
#      note annote keywords abstract copyright));
        ['citation_keywords', 'keywords'],
        ['dc.description', 'abstract'],
        );

    $entry->delete('keywords') if $entry->exists('keywords') and ($entry->get('keywords') eq '');
    $entry->set('author', $html->authors()) if $html->authors();
    $entry->set('pages', $html->get('pages')->[0]) if $html->exists('pages');

    my ($year, $month) = $html->date('dc.date');
    $entry->set('year', $year);
    $entry->set('month', $month);

    $mech->follow_link(text => 'BibTex');
    my $f = parse_bibtex(decode('utf8', $mech->content()));

    if ($entry->type() eq 'inproceedings') { # IEEE gets this all wrong
        $entry->set('series', $f->get('journal')) if $f->exists('journal');
        $entry->delete('journal');
    }
    $entry->set('address', $f->get('address')) if $f->exists('address');
    $entry->set('volume', $f->get('volume')) if $f->exists('volume');
    update($entry, 'volume', sub { $_ = undef if $_ eq "0" });

    return $entry;
}

# IEEE is evil because they require a subscription just to get bibliography data
# (they also use JavaScript to implement simple links)
sub parse_ieeexplore {
    my ($mech, $fields) = @_;
    my ($record) = $mech->content() =~ m[var recordId = "(\d+)";];

    # Ick, work around javascript by hard coding the URL
    $mech->get("http://ieeexplore.ieee.org/xpl/downloadCitations?".
               "recordIds=$record&".
               "fromPage=&".
               "citations-format=citation-abstract&".
               "download-format=download-bibtex");
    my $cont = $mech->content();
    $cont =~ s/<br>//gi;
    $cont =~ s/month=([^,\.{}"]*?)\./month=$1/;
    my $entry = parse_bibtex($cont);

    $mech->back();

    my ($month) = $mech->content() =~ m[\&publicationDate=([a-z0-9\., -]+)\&]is;
    if (defined $month) {
        $month =~ s[[0-9\., ]][]isg;
        $month =~ s[^-*][];
        $month =~ s[-*$][];
        $entry->set('month', $month);
    }

    my ($isbn) = $mech->content() =~ m[\&isbn=([0-9X-]+)\&]is;
    $entry->set('isbn', $isbn) if defined $isbn;

    return $entry
}

sub parse_jstor {
    my ($mech) = @_;

    # Ick, not only does JSTOR hide behind JavaScript, but
    # it hides the link for downloading BibTeX if we are not logged in.
    # We get around this by hard coding the URL that we know it should be at.
    my ($suffix) = $mech->content() =~
        m[Stable URL: .*?://www.jstor.org/stable/(\d+)\W];
    $mech->post("http://www.jstor.org/action/downloadCitation?userAction=export&format=bibtex&include=abs",
                {'noDoi'=>$suffix, 'doi'=>"10.2307/$suffix"});

    my $cont = $mech->content();
    $cont =~ s[\@comment{.*$][]gm; # hack to avoid comments
    $cont =~ s[JSTOR CITATION LIST][]g; # hack to avoid junk chars
    my $entry = parse_bibtex($cont);
    $entry->set('doi', '10.2307/' . $suffix);
    my ($month) = ($entry->get('jstor_formatteddate') =~ m[^(.*?)( \d\d?)?, \d\d\d\d$]);
    $entry->set('month', $month) if defined $month;
    $mech->back();

    $entry->set('title', $mech->content() =~ m[<div class="mainCite.*?"><h2 class="h3">(.*?)</h2>]);

    issn($entry,
         [$mech->content() =~ m[>ISSN: (\d{7}[0-9X])<]],
         [$mech->content() =~ m[>E-ISSN: (\d{7}[0-9X])<]]);

    return $entry;
}

sub parse_ios_press {
    my ($mech) = @_;

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

    my ($isbn) = ($mech->content() =~ m[>ISBN</td><td.*?>(.*?)</td>]i);
    $entry->set('isbn', $isbn) if defined $isbn;

    my ($abstract) = ($mech->content() =~ m[<div class="abstract">\s*<p>(.*?)</p>\s*</div>]i);
    $entry->set('abstract', $abstract) if defined $abstract;

    return $entry;
}

sub parse_wiley {
    my ($mech) = @_;
    $mech->follow_link(url_regex => qr[/abstract]) if $mech->find_link(url_regex => qr[/abstract]);
    $mech->follow_link(text => 'Export Citation for this Article');
    $mech->submit_form(with_fields => {
        'fileFormat' => 'BIBTEX', 'hasAbstract' => 'CITATION_AND_ABSTRACT'});
    my $entry = parse_bibtex(decode('utf8', $mech->content()));
    $mech->back(); $mech->back();

    # Fill in the missing month
    my ($month) = ($mech->content() =~ m[<span id="issueDate">((\w|\/)*) \d*</span>]);
    $entry->set('month', $month) if $month;
    # Choose the title either from bibtex or HTML based on whether we thing the BibTeX has the proper math in it.
    $entry->set('title', $mech->content() =~ m[<h1 class="articleTitle">(.*?)</h1>]s)
        unless $entry->get('title') =~ /\$/;

    # Ugh! Both the BibTeX and the HTML have problems.  Here we try to
    # pick out the best from each.  The HTML is usually better except that
    # it uses <img> takes for some math.
    my $bibtex_abstr = $entry->get('abstract');
    my ($html_abstr) = ($mech->content() =~ m[<div id="abstract"><h3>Abstract</h3>(<div class="para">.*?</div>)</div>]);
    my $math_img = qr[<img [^>]*?>]; # We could use a more complicated regex, but this is good enough

    # Try to find the diff between the BibTeX and HTML
    my $diff = Algorithm::Diff->new(
        # Don't let "$...$" and "\documentclass...\end{document}" be split apart
        [grep {defined $_} (split m[(\$.*?\$|\\documentclass.*?\\end\{document\})?], $bibtex_abstr)],
        # Don't let "&charCode;", "<img...>" or "<span...><img...></span>" be split apart
        [grep {defined $_} (split m[(\&[^;]*?;|$math_img|<span[^>]*?>$math_img</span>)?], $html_abstr)]);
    my $abstract = '';
    while ($diff->Next()) {
        my $html = join('', $diff->Items(2));
        $html =~ s[([{}])][\\$1]g; # Escape the HTML while we know it is still HTML
        if ($html =~ m[$math_img]) {
            # Replace images (and special characters surrounding it) with BibTeX.
            # (By substituting we keep around things like </em> and the start or <em> at the end
            $html =~ s[(\&[^;]*?;)*($math_img|<span[^>]*?>$math_img</span[^>]*?>)(\&[^;]*?;)*]
                      [@{[join('', $diff->Items(1))]}]is;
        }
        $abstract .= $html;
    }

    # Finally, we clean up and use this abstract
    $entry->set('abstract', $abstract);

    update($entry, 'abstract', sub { s[\\documentclass\{article\} \\usepackage\{mathrsfs\} \\usepackage\{amsmath,amssymb,amsfonts\} \\pagestyle\{empty\} \\begin\{document\} \\begin\{align\*\}(.*?)\\end\{align\*\} \\end\{document\}][\\ensuremath{$1}]isg; });
    update($entry, 'abstract', sub { s[<div class="para">(.*?)</div>][\n\n$1\n\n]isg });
    update($entry, 'abstract',
           sub { s[(Copyright )?(.|&copy;) \d\d\d\d John Wiley (.|&amp;) Sons, (Ltd|Inc)\.\s*][] });
    update($entry, 'abstract',
           sub { s[(.|&copy;) \d\d\d\d Wiley Periodicals, Inc\. Random Struct\. Alg\..*, \d\d\d\d][] });
    return $entry;
}

sub parse_oxford_journals {
    my ($mech) = @_;

    my $html = Text::MetaBib::parse($mech->content());
    my $entry = parse_bibtex("\@article{unknown_key,}");

    $entry->set('author', $html->authors()) if $html->authors();
    $entry->set('pages', $html->pages()) if $html->pages();
    $html->exists($_->[0]) and $entry->set($_->[1], join(' ; ', @{$html->get($_->[0])})) for (
#      editor affiliation title
        ['citation_title', 'title'],
#      howpublished booktitle journal volume number series
        ['citation_journal_title', 'journal'], ['citation_volume', 'volume'],
        ['citation_issue', 'number'], # patent_number, technical_report_number
#      type school institution location
#      chapter pages
#      edition month year
#      organization publisher address
        ['dc.publisher', 'publisher'],
#      language isbn issn doi url
        ['dc.language', 'language'],
        ['citation_isbn', 'isbn'], ['citation_issn', 'issn'], ['citation_doi', 'doi'],
#        ['citation_mjid', 'mjid'],
#        ['citation_pdf_url', 'pdf_url'],
#      note annote keywords abstract copyright));        
        );

    my ($year, $month) = $html->date('dc.date');
    $entry->set('year', $year);
    $entry->set('month', $month);

    my ($title) = $mech->content =~ m[<h1 id="article-title-1" itemprop="headline">\s*(.*?)\s</h1>]si;
    $entry->set('title', $title) if defined $title;
    my ($abstract) = ($mech->content() =~ m[>\s*Abstract\s*</h2>\s*(.*?)\s*</div>]si);
    $entry->set('abstract', $abstract) if defined $abstract;

    #$entry->set('address', 'Oxford, UK');
    update($entry, 'issn', sub { s[ *; *][/]g; });

    issn($entry,
         [$mech->content() =~ m[Print ISSN (\d\d\d\d-\d\d\d[0-9X])]],
         [$mech->content() =~ m[Online ISSN (\d\d\d\d-\d\d\d[0-9X])]]);

    return $entry;
}

sub issn {
    my ($entry, $print, $online) = @_;
    my ($print_issn) = @$print;
    my ($online_issn) = @$online;
    if ($print_issn and $online_issn) {
        $entry->set('issn', "$print_issn (Print) $online_issn (Online)");
    } elsif ($print_issn or $online_issn) {
        $entry->set('issn', $print_issn || $online_issn);
    }
}

1;
