# This software has been replaced by [BibScrape](https://github.com/adamsmd/BibScrape/) and is no longer maintained.  

bib-scrape
================

This is a BibTeX scraper for collecting BibTeX entries from the
websites of computer-science academic publishers.  I use it personally
to make preparing my BibTeX files easier.  Currently it supports

 - ACM `<acm.org>`,
 - Springer `<link.springer.com>`,
 - Science Direct `<sciencedirect.com>`,
 - IEEE Computer Society `<computer.org>`,
 - IEEE Explore `<ieeexplore.ieee.org>`,
 - Cambridge Journals `<journals.cambridge.org>`,
 - Oxford Journals `<oxfordjournals.org>`,
 - JSTOR `<jstor.org>`,
 - IOS Press `<iospress.metapress.com>`, and
 - Wiley `<onlinelibrary.wiley.com>`.

In addition, this scraper fixes common problems with the BibTeX that
these services provide.  For example, it fixes:

 - the handling of Unicode and other formatting (e.g. subscripts) in titles;
 - the incorrect use of the 'issue' field instead of the 'number' field;
 - the format of the 'doi' and 'pages' fields;
 - the use of macros for the 'month' field; and
 - *numerous* miscellaneous problems with specific publishers.

Usage
================
The basic usage is

    ./bib-scrape.pl URL ...

Each URL is the page of an article you want to scrape.  Note that if
you have a DOI, then prefixing 'https://doi.org/' on the DOI will
form a usable URL.

Examples:

    ./bib-scrape.pl 'https://portal.acm.org/citation.cfm?id=1614435'
    ./bib-scrape.pl 'https://www.springerlink.com/content/nhw5736n75028853/'
    ./bib-scrape.pl 'https://doi.org/10.1007/BF01975011'

For more details on usage and command-line flags run:

    ./bib-scrape.pl --help

Installation
================
This program is not designed to be installed(*).  You just run it directly
from where you unpacked it.  However, there are Perl modules that it depends
on.

IMPORTANT: Be sure to always run the program from the directory where
you unpacked it.  If you run the program from any other directory, it
will not be able to find the `config/names.cfg` and `config/actions.cfg
files.

(*) There are two reasons for this.  First, Perl doesn't have a very
good method of packaging applications.  Second, I don't know how to
make the program find `config/names.cfg` and `config/actions.cfg` in
such a packaging.  I would welcome help in preparing a better packaging
solution.

Global/Root Installation
----------------
If you want to install the module dependencies globally to `/usr/share/perl5`,
do the following.

1. Ensure that you have `sudo` permission.
2. Ensure that `Module::Build` installed by running `sudo cpan Module::Build`.
3. Generate the `Build` script by running `perl Build.PL`.
4. Install the dependencies by running `sudo ./Build installdeps`.

Local/Home Installation
----------------
If you want to install the module dependencies locally to
your home directory, do the following.

1. Install and Setup and install [`local::lib`](https://metacpan.org/pod/local::lib).
   See [The Bootstrapping Technique](https://metacpan.org/pod/local::lib#The-bootstrapping-technique) for instructions.
2. Ensure that `Module::Build` installed by running `cpan -I Module::Build`.
   (The `-I` tells `cpan` to use `local::lib`.)
3. Generate the `Build` script by running `perl Build.PL`.
4. Install the dependencies by running `./Build installdeps`.

Disclaimer
================
Please use this software responsibly.  You are responsible for how you
use it.  It does not contain any bandwidth limiting code as most
publisher pages respond slowly enough that it is usually not
necessary.  However, I've only tested it for preparing small
bibliographies with fewer than 100 entries.  If you try to scrape too
many at a time, I make no guarantees that you won't accidentally DoS
the publisher.

Feedback
================
If you have any problems or suggestions, feel free to contact me.  I
am particularly interested in any articles on which that bib-scrape breaks
or formats incorrectly, and any BibTeX fixes that you think should be
included.

Until I build up my test suite, I am also interested in collecting
pages that test things like articles that have Unicode in their titles
and so forth.

However, since I am the only maintainer and there are hundreds of
publishers, I have to limit what publishers to support.  If you find a
computer-science publisher that I forgot, let me know and I'll add it.
I'm more hesitant to add publishers from other fields.  Also, as a
matter of policy, I prefer to scrape from publisher pages instead of
from aggregators (e.g. BibSonomy, DBLP, etc.) as aggregators are much
less predictable in the sorts of errors they introduce.

You can find my contact information at https://michaeldadams.org/

Features
================
 - All fields except 'doi' and 'url' are escaped.  The 'doi' and 'url' fields
   are not escaped on the assumption that you are using the Latex url package.

 - Fields are stripped to bare values. For example, leading 'ABSTRACT', 'p.' or 'doi:'
   are stripped from the 'abstract', 'pages' and 'doi' fields respectively.

 - The 'url' field is omitted if it just points back to the publisher's page.

 - The 'note' field is omitted if it just contains the 'doi'.

 - Unicode and some form formatting (e.g. superscripts) use the correct Latex codes.

 - Ranges (e.g. pages) use "--" instead of "-".  (Note, this be
   incorrect for the 'number' field of a @techreport.)

 - Full journal names are used when available instead of
   abbreviations.

 - Fields are put in a standard order.

 - Entry keys are generated as "last-name-of-first-author:year:doi"
   or when there is no doi as "last-name-of-first-author:year".
   (This needs improvement.)

 - The 'issue' and 'keyword' fields are renamed to 'number' and
   'keywords' respectively.

 - For ACM, the conference proceedings are preferred over SIGPLAN Notices.

 - And much more ...

Limitations
================
 - JSTOR imposes strict rate limiting.  You may have `Error GETing`
   errors if you try to get the BibTeX for multiple papers in a row.

 - Basically don't trust the "title", "author" and "abstract" fields.
   Other fields will generally be right, but these fields often have
   Latex code that don't get preserved by the publishers. Though
   bib-scrape will do it's best, the results are often spotty.
   Example $O$$($n$)$.

 - IOS press often doesn't preserve mathematical italics, and
   you can get better results by visiting the corresponding page on SpringerLink.

 - Data from the publishers is often wrong.  In particular, formatting
   of author names is the biggest problem.  The data from the
   publishers is often incomplete or incorrect.  For example, I've
   found 'Blume' misspelled as 'Blu', 'Bruno C.d.S Oliviera' listed as
   'Bruno Oliviera' and 'Simon Peyton Jones' listed as 'Jones, Simon
   Peyton'.  See the `config/names.cfg` file for how to fix these.

 - Many heuristics are involved in scraping and fixing the data.  This in an inherently fuzzy area.

 - Often 2-3 pages have to be loaded and publisher pages can be slow.
   In total it takes around 1 second per citation.

 - There are many BibTeX problems that this program can't fix:
   - The 'howpublished' field shouldn't be used for URLs.  Use the url field for that.
   - Names should be 'von last, first, jr' as it is the only unambiguous format in BibTeX.
   - Proper names in titles should be capitalized with braces (e.g. "{H}askell").

 - Complex math in titles or abstracts is likely to break.  A couple superscripts and
   Greek characters are fine, but more than that is trouble.

License
================
Copyright (c) 2011-2013, Michael D. Adams `<https://michaeldadams.org/>`

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see `<https://www.gnu.org/licenses/>`.
