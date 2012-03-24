package Text::ISBN;

# http://www.isbn-international.org/page/ranges
# http://www.isbn-international.org/agency?rmxml=1
# http://pcn.loc.gov/isbncnvt.html

use warnings;
use strict;

use Carp;
use Text::ISBN::Data;

sub check_digit {
    my ($mod, $consts, $digits) = @_;
    $digits =~ s/-//g;
    my @digits = split(//, $digits);
    my $sum = 0;
    for my $i (0..$#$consts) {
        $sum += $digits[$i] * $consts->[$i];
    }
    my $digit = ($mod - $sum % $mod) % $mod;
    return $digit == 10 ? 'X' : $digit;
}

sub check_digit10 { check_digit(11, [10,9,8,7,6,5,4,3,2], @_); }
sub check_digit13 { check_digit(10, [1,3,1,3,1,3,1,3,1,3,1,3], @_); }

sub canonical {
    my ($isbn, $isbn13, $sep) = @_;
    $isbn =~ s/[- ]//g;
    my @digits = split(//, $isbn);

    if ($isbn =~ m/^[0-9]{10}$/) {
        my $check = check_digit10($isbn); #check_digit(11, [10,9,8,7,6,5,4,3,2], @digits[0..8]);
        croak "Bad check digit in ISBN10.  Expecting $check in $isbn" unless $isbn =~ /$check$/;
        $isbn = '978' . $isbn;
    } elsif ($isbn =~ m/^[0-9]{12}[0-9Xx]$/) {
        my $check = check_digit13($isbn); #check_digit(10, [1,3,1,3,1,3,1,3,1,3,1,3], @digits[0..11]);
        croak "Bad check digit in ISBN13.  Expecting $check in $isbn" unless $isbn =~ /$check$/;
    } else {
        croak "Invalid digits or wrong number of digits in ISBN: $isbn";
    }

    # By this point we know it is a valid ISBN13 w/o dashes but with a possibly wrong check digit
    $isbn = Text::ISBN::Data::hyphenate($isbn);

    if ($isbn13 or $isbn !~ s/^978-//) {
        my $check = check_digit13($isbn);
        $isbn =~ s/.$/$check/;
    } else {
        my $check = check_digit10($isbn);
        $isbn =~ s/.$/$check/;
    }

    $isbn =~ s/-/$sep/g;

    return $isbn;
}

#print canonical('0-201-53082-1', 0, ''), "\n";
#print canonical('0-201-53082-1', 0, '-'), "\n";
#print canonical('0-201-53082-1', 1, ''), "\n";
#print canonical('0-201-53082-1', 1, '-'), "\n";
#
#print canonical('978-1-56619-909-4', 0, ''), "\n";
#print canonical('978-1-56619-909-4', 0, '-'), "\n";
#print canonical('978-1-56619-909-4', 1, ''), "\n";
#print canonical('978-1-56619-909-4', 1, '-'), "\n";
#
#print canonical('979-10-00-12222-9', 0, ''), "\n";
#print canonical('979-10-00-12222-9', 0, '-'), "\n";
#print canonical('979-10-00-12222-9', 0, ' '), "\n";
#print canonical('979-10-00-12222-9', 1, ''), "\n";
#print canonical('979-10-00-12222-9', 1, '-'), "\n";
#print canonical('979-10-00-12222-9', 1, ' '), "\n";

1;
