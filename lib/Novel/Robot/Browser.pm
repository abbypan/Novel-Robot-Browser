# ABSTRACT: 自动化获取网页内容，并解码为unicode
package Novel::Robot::Browser;

use strict;
use warnings;
use utf8;

use Encode::Detect::CJK qw/detect/;
use Encode;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Moo;
use LWP::UserAgent;

has retry => ( is => 'rw', default => sub {3}, );

sub get_url_ref {
    my ( $self, $url, $post_vars ) = @_;

    $self->{http} ||= $self->init_browser();

    my $response;
    for my $i ( 1 .. $self->{retry} ) {
        $response =
              $post_vars
            ? $self->{http}->post( $url, $post_vars )
            : $self->{http}->get($url);
        last if ( $response->is_success );
    } ## end for my $i ( 1 .. $self->...)

    return unless ( $response->is_success );

    my $html;
    my $c = $response->content;
    gunzip \$c => \$html;

    my $charset = detect($html);
    $html = decode( $charset, $html, Encode::FB_XMLCREF );

    return \$html;
} ## end sub get_url_ref

sub init_browser {
    my ($self) = @_;

    my $browser = LWP::UserAgent->new( keep_alive => 1 );
    $browser->cookie_jar( {} );
    push @{ $browser->requests_redirectable }, 'POST';

    my %browser_opt = (
        'Accept'          => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Charset'  => 'gb2312,utf-8;q=0.7,*;q=0.7',
        'Accept-Encoding' => "gzip, deflate",
        'User-Agent' => 'Moozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0; MALC)',
        'Accept-Language' => "zh,zh-cn;q=0.8,zh-tw;q=0.6,en-us;q=0.4,en;q=0.2",
    );
    $browser->default_header( $_ => $browser_opt{$_} ) for keys(%browser_opt);

    return $browser;
} ## end sub init_browser

no Moo;

1;
