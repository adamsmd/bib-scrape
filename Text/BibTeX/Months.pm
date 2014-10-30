package Text::BibTeX::Months;

use Exporter qw(import);

use Text::BibTeX;

our @EXPORT = qw(num2month str2month);
our @EXPORT_OK = qw();

#Text::BibTeX::Bib::month_names

my @long_names = qw(
  january february march april may june july august september october november december);

my @macro_names = qw(jan feb mar apr may jun jul aug sep oct nov dec);

my %months;
$months{$macro_names[$_]} = $macro_names[$_] for (0..@long_names);
$months{$long_names[$_]} = $macro_names[$_] for (0..@long_names);
$months{'sept'} = 'sep';

Text::BibTeX::add_macro_text($_, $months{$_}) for (keys %months);

sub macro { my $x = shift; $x and [Text::BibTeX::BTAST_MACRO, $x] or undef }
sub num2month { $_[0] =~ m[^\d+$] and macro($macro_names[shift()-1]) or die "Invalid month number" }
sub str2month { macro($months{lc shift()}) }

1;
