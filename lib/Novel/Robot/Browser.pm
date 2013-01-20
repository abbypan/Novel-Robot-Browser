# ABSTRACT: 自动化获取网页内容，并解码为unicode

package Novel::Robot::Browser;

use strict;
use warnings;
use utf8;

use Encode::Detect::CJK qw/detect/;
use Encode;
#use HTTP::Tiny;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use Moo;
use HTTP::Request;
use LWP::UserAgent;

has retry => ( is => 'rw', default => sub {3}, );

sub get_url_ref {
    my ( $self, $url, $post_vars ) = @_;

    my $req;
    if ($post_vars) {
        $req = HTTP::Request->new(POST => $url);
        $req->content_type('application/x-www-form-urlencoded');

        my $post_data = $self->make_post_data($post_vars);
        $req->content($post_data);
    }
    else {
        $req = HTTP::Request->new(GET => $url);
    }

    $self->{http} ||= $self->init_browser();

    my $response;
    for my $i ( 1 .. $self->{retry} ) {
        $response = $self->{http}->request($req);
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
            'User-Agent' =>
                'Moozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0; MALC)',
            'Accept-Language' => "zh,zh-cn;q=0.8,zh-tw;q=0.6,en-us;q=0.4,en;q=0.2",
    );
    $browser->default_header($_ => $browser_opt{$_}) for keys(%browser_opt);

    return $browser;
} ## end sub init_browser

sub make_post_data {
    my ( $self, $post_vars ) = @_;

    my @params;
    while ( my @pair = each %$post_vars ) {
        push @params, join( "=", @pair );
    }

    my $data = join( "&", @params );

    return $data;
} ## end sub make_post_data

no Moo;

1;
