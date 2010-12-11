#!/usr/bin/perl

#use warnings;
use strict;

use LWP::Simple;

my ($url) = $ARGV[0];
my ($page) = get($url); # Get the page

# Get the ids
my ($pid, $id) = $page =~ m[<meta name="citation_abstract_html_url" content="http://portal\.acm\.org/citation\.cfm\?id=(\d+)\.(\d+)">];

# Get the BibTeX
my $bib = get("http://portal.acm.org/downformats.cfm".
              "?id=$id&parent_id=$pid&expformat=bibtex");

# TODO: adjust key

# Normalize doi field (remove any "http://hostname/" at the front)
$bib =~ s[doi = {http://[^/]+/][doi = {];

# Fix abbriviations in journal field
my ($journal) = $page =~ m[<meta name="citation_journal_title" content="(.+)">];
$bib =~ s[journal = {.+}][journal = {$journal}];

# Get the abstract
#  TODO: Paragraphs? There is no marker but often we get ".<Uperchar>".
#    But sometimes we get <p></p>
#  TODO: HTML encoding?
my $abstract =
  get("http://portal.acm.org/tab_abstract.cfm?id=$id&usebody=tabbody");
($abstract) = $abstract =~
  m[<div style="display:inline">(?:<par>)?(.+?)(?:</par>)?</div>];
# TODO: no need to remove par?
$bib =~ s[}[^}]*$][ abstract = {$abstract},\n}]s if $abstract;

# Print the BibTex;
print $bib, "\n\n";


# TODO: get PDF
# TODO: handle multiple entries

# BUG: download bibtex link is broken at
#  at http://portal.acm.org/citation.cfm?id=908021&CFID=112731887&CFTOKEN=92268833&preflayout=tabs

# Science Direct
# SpringerLink

@article{web,
 author = {Hinze, Ralf and Jeuring, Johan},
 title = {Weaving a web},
 journal = {Journal of Functional Programming},
 volume = {11},
 number = {6},
 year = {2001},
 month = {November},
 pages = {681--689},
 doi = {10.1017/S0956796801004129},
 publisher = {Cambridge University Press},
 address = {New York, NY, USA},
 }


@inproceedings{SYBR1,
  title = {``{Scrap} Your Boilerplate'' Reloaded},
  author = {Ralf Hinze and Andres L\"{o}h and Bruno C. d. S. Oliveira},
  booktitle = {Functional and Logic Programming},
  publisher = {Springer Berlin / Heidelberg},
  abstract = {The paper Scrap your boilerplate () introduces a combinator library for generic programming that offers generic traversals and queries. Classically, support for generic programming consists of two essential ingredients: a way to write (type-)overloaded functions, and independently, a way to access the structure of data types.) introduces a combinator library for generic programming that offers generic traversals and queries. Classically, support for generic programming consists of two essential ingredients: a way to write (type-)overloaded functions, and independently, a way to access the structure of data types.seems to lack the second. As a consequence, it is difficult to compare with other approaches such as PolyP or Generic Haskell. In this paper we reveal the structural view thatseems to lack the second. As a consequence, it is difficult to compare with other approaches such as PolyP or Generic Haskell. In this paper we reveal the structural view thatbuilds upon. This allows us to define the combinators as generic functions in the classical sense. We explain thebuilds upon. This allows us to define the combinators as generic functions in the classical sense. We explain theapproach in this changed setting from ground up, and use the understanding gained to relate it to other generic programming approaches. Furthermore, we show that theapproach in this changed setting from ground up, and use the understanding gained to relate it to other generic programming approaches. Furthermore, we show that theview is applicable to a very large class of data types, including generalized algebraic data types.view is applicable to a very large class of data types, including generalized algebraic data types.},
  volume = {3945},
  series = {Lecture Notes in Computer Science},
  year = {2006},
  pages = {13--29},
  subject_collection = {Computer Science},
  doi = {10.1007/11737414_3},
}

  issn = {0169-2968 (Print) 1875-8681 (Online)},
@Article{differentiating-data-structures,
  author =       {Michael Abbott and Thorsten Altenkirch and Conor McBride and Neil Ghani},
  title =        {$\partial$ for Data: Differentiating Data Structures},
  journal =      {Fundamenta Informaticae},
  year =         {2005},
  volume =    {65},
  number =    {1--2},
  pages =     {1--28},
  month =     {February--March},
  publisher = {IOS Press},
  address = {Amsterdam, The Netherlands},
}
