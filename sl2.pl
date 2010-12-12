#!/usr/bin/env perl

use warnings;
#use LWP::Simple;
use LWP 5.64;
use File::Temp qw/tempfile/;
use WWW::Mechanize;
use Encode;

binmode STDOUT, ":utf8";


$url = "http://www.springerlink.com/content/nhw5736n75028853/export-citation/";

my $mech = WWW::Mechanize->new( autocheck => 1 );
$mech->quiet(1);
$mech->agent_alias( 'Windows IE 6' );


$mech->get( $url );
my $form = $mech->form_name("aspnetForm");

$mech->field('ctl00$ContentPrimary$ctl00$ctl00$Export' , "AbstractRadioButton");
$mech->field('ctl00$ContentPrimary$ctl00$ctl00$Format' , "RisRadioButton");
my $res = $mech->select('ctl00$ContentPrimary$ctl00$ctl00$CitationManagerDropDownList' , "BibTex");
#if (!$res) {
#	# Books - can't get citation so get from crossref.  Need DOI first.
#	# hacky... look for <dd>10.xxxxxx</dd>
#	# TODO - crossref.tcl can't parse crossref books yet....
#	my $c = $mech->content();
#	if ($c =~ /<dd>(10\.\d\d\d\d\/[^<]+)<\/dd>/) {
#		# fake a RIS - all we need is the DOI bit
#		$ris= "UR  - http://dx.doi.org/".$1;
#	} else {
#		$ris = "";
#	}
#} else {
#foreach (@inputs) {
	#print "$_\n";
	#print $_->name . " => " . $_->value."\n";
#}
#$mech->add_header( "Accept-Charset" => 'utf-8' );

my $response = $mech->click('ctl00$ContentPrimary$ctl00$ctl00$ExportCitationButton');

#
# This seems very fragile - $ris is already UTF8 bytes.
# There are no encoding headers in the response (always) but I think
# browsers should default to UTF-8, whereas mechanize seems to assume something
# like Latin-1
#
#$ris = $response->decoded_content({default_charset => "UTF-8"});
$ris = $response->content();
$ris = decode("utf8", $ris);

# strip UTF BOM
#$ris =~ s/^\xEF\xBB\xBF//;
# Hmmm - above doesn't work so use hammer
#$ris =~ s/^[^A-Z]+//;

#$ris =~ s/\r//g;

print $ris;
unless ($ris =~ m{ER\s+-}) {
	print "status\terr\tCouldn't extract the details from SpringerLink's 'export citation'\n" and exit;
}

#}
#Generate linkouts and print RIS:
print "begin_tsv\n";

# Springer seem to use DOIs exclusively
#DOI linkout
#if ($ris =~ m{doi:([0-9a-zA-Z_/.:-]*)}) {
#if ($ris =~ m{doi:(\S*)}) {

my $have_linkouts = 0;
if ($ris =~ m{UR  - http://dx.doi.org/([0-9a-zA-Z_/.:-]+/[0-9a-zA-Z_/.:-]+)}) {
	$doi = $1;
	chomp $doi;
	print "linkout\tDOI\t\t$doi\t\t\n";
	$have_linkouts = 1;
}
if ($ris =~ m{UR  - http://www.springerlink.com/content/([^/\r\n]+)}) {
	$slink = $1;
	chomp $slink;
	print "linkout\tSLINK\t\t$slink\t\t\n";
	$have_linkouts = 1;
} elsif ($slink) {
	chomp $slink;
	print "linkout\tSLINK\t\t$slink\t\t\n";
	$have_linkouts = 1;
}

if (!$have_linkouts) {
	print "status\terr\tThis document does not have a DOI or a Springer ID, so cannot make a permanent link to it.\n" and exit;
}

print "end_tsv\n";
print "begin_ris\n";
print "$ris\n";
print "end_ris\n";
print "status\tok\n";

