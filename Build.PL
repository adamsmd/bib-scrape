#!/usr/bin/perl
use Module::Build;
Module::Build->new(
configure_requires => { 'Module::Build' => 0.38 },
dist_name => 'bib-scrape',
dist_version_from => 'bib-scrape.pl',
dist_abstract => 'A BibTeX scraper for collecting BibTeX entries from the websites of computer-science academic publishers.',
requires => {
  Algorithm::Diff          => 0,
  Carp                     => 0,
  Class::Struct            => 0,
  Encode                   => 0,
  Exporter                 => 0,
  Getopt::Long             => 0,
  HTML::Entities           => 0,
  HTML::HeadParser         => 0,
  Locale::Language         => 0,
  Safe                     => 0,
  Scalar::Util             => 0,
  Text::BibTeX             => 0,
  Text::BibTeX::Name       => 0,
  Text::BibTeX::NameFormat => 0,
  Text::BibTeX::Value      => 0,
  WWW::Mechanize           => 0,
  XML::Parser              => 0,
  vars                     => 0,
})->create_build_script;
