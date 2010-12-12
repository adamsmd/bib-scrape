use WWW::Mechanize;
use HTML::TokeParser;
use HTML::HeadParser;
#my $url = 'http://portal.acm.org/citation.cfm?id=1863543.1863551';
#my $mech = WWW::Mechanize->new(autocheck => 1);
#$mech->get($url);
#print $mech->find_link(tag => 'meta') ? 'found' : 'not found', "\n";

$head = new HTML::HeadParser;
print $head->parse("<html><head><meta name='citation_journal_title' content='foo'></head></html>"), "\n";
print $head->header('X-Meta-citation_journal_title'), "\n";

__END__

my %link_tags = (
    a      => 'href',
    area   => 'href',
    frame  => 'src',
    iframe => 'src',
    link   => 'href',
    meta   => 'content',
);

$links = [];
$content = "<meta name='citation_journal_title' content='foo'>";
my $parser = HTML::TokeParser->new(\$content);
while ( my $token = $parser->get_tag( keys %link_tags ) ) {
    print join("\n", @$token);
#    my $link = $self->_link_from_token( $token, $parser );
#    push( @{$self->{links}}, $link ) if $link;
} # while
