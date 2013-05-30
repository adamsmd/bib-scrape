#!/bin/bash
(
ls LICENSE MANIFEST README Build.PL
ls bib-scrape.pl test.sh
find Text TeX -name \*.pm
ls names.txt action.txt sites.txt
find tests -name \*.t
#ls unicode/{README,TODO,UnicodeData.txt,unicode.xml,unicode.xml.old,unimathsymbols.txt}
#ls unicode/*.pl
#ls unicode/test/*.tex
#find unicode -name \*.pm
) > MANIFEST

perl <<'EOF' >Build.PL
open(MAN, "MANIFEST");
my @manifest = map {s[/][::]g; s[\.pm$][]; chomp; $_} grep {/\.pm$/} <MAN>;
push @manifest, 'strict', 'utf8', 'warnings';
my @reqs = grep {/^(\S+)\s/; not (grep {$_ eq $1} @manifest)} `scan_prereqs --combine bib-scrape.pl Text TeX`;

print <<EOT;
#!/usr/bin/perl
use Module::Build;
Module::Build->new(
configure_requires => { 'Module::Build' => 0.38 },
dist_name => 'bib-scrape',
dist_version_from => 'bib-scrape.pl',
dist_abstract => 'A BibTeX scraper for collecting BibTeX entries from the websites of computer-science academic publishers.',
requires => {
EOT
print join("", map {s/=/=>/; s/\n$/,\n/; s/^/  /; $_} @reqs);
print <<EOT;
})->create_build_script;
EOT
EOF

perl Build.PL
./Build dist

#PP="pp --addfile=names.txt;scripts/names.txt --addfile=nouns.txt;scripts/nouns.txt"
#$PP -p -o bib-scrape-par.par bib-scrape.pl
#$PP -P -o bib-scrape-par.pl bib-scrape.pl
