package Text::RIS;

use Exporter qw(import);

use Text::BibTeX;

our @EXPORT = qw(num2month str2month);
our @EXPORT_OK = qw();

#Text::BibTeX::Bib::month_names

my @months = (
    undef,
    [Text::BibTeX::BTAST_MACRO, 'jan'],
    [Text::BibTeX::BTAST_MACRO, 'feb'],
    [Text::BibTeX::BTAST_MACRO, 'mar'],
    [Text::BibTeX::BTAST_MACRO, 'apr'],
    [Text::BibTeX::BTAST_MACRO, 'may'],
    [Text::BibTeX::BTAST_MACRO, 'jun'],
    [Text::BibTeX::BTAST_MACRO, 'jul'],
    [Text::BibTeX::BTAST_MACRO, 'aug'],
    [Text::BibTeX::BTAST_MACRO, 'sep'],
    [Text::BibTeX::BTAST_MACRO, 'oct'],
    [Text::BibTeX::BTAST_MACRO, 'nov'],
    [Text::BibTeX::BTAST_MACRO, 'dec']);

sub num2month { $months[$_[0]] }

my %months = (
    $months[1]->[1] => $months[1],
    'january' => $months[1],
    $months[2]->[1] => $months[2],
    'february' => $months[2],
    $months[3]->[1] => $months[3],
    'march' => $months[3],
    $months[4]->[1] => $months[4],
    'april' => $months[4],
    $months[5]->[1] => $months[5],
    'may' => $months[5],
    $months[6]->[1] => $months[6],
    'june' => $months[6],
    $months[7]->[1] => $months[7],
    'july' => $months[7],
    $months[8]->[1] => $months[8],
    'august' => $months[8],
    $months[9]->[1] => $months[9],
    'september' => $months[9],
    'sept' => $months[9],
    $months[10]->[1] => $months[10],
    'october' => $months[10],
    $months[11]->[1] => $months[11],
    'november' => $months[11],
    $months[12]->[1] => $months[12],
    'december' => $months[12]);

sub str2month { $months{$_[0]} }

for my $i (keys %months) {
    Text::BibTeX::add_macro_text($i, $months{$i}[1]);
}

1;

__END__
