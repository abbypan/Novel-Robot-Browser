# ABSTRACT: 自动化获取网页内容，并解码为unicode

=pod

=encoding utf8

=head1 FUNCTION

=head2 request_url
  
    my $browser = Novel::Robot::Browser->new();
	
    my $url = 'http://www.jjwxc.net/onebook.php?novelid=2456';

    my $content_get_ref = $browser->request_url($url);

    my $form_url = 'http://www.jjwxc.net/search.php';

    my $post_data = {
		'key1' => 'value1', 
		'key2' => 'value2', 
    };

    my $content_post_ref = $browser->request_url($form_url, $post_data);

=cut

package Novel::Robot::Browser;

use strict;
use warnings;
use utf8;

our $VERSION = 0.08;

use Encode::Detect::CJK qw/detect/;
use Encode;
use WWW::Mechanize;
use Moo;

has retry => ( is => 'rw', default => sub { 3 }, );

has browser => ( is => 'rw', default => \&init_browser );

sub init_browser {
    my ($self) = @_;
    my $http = WWW::Mechanize->new();

    my %default_headers = (
        'Accept' =>
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Charset'  => 'gb2312,utf-8;q=0.7,*;q=0.7',
        'Accept-Encoding' => "gzip, deflate",
        'Connection'      => 'keep-alive',
        'User-Agent' =>
'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0; MALC)',
        'Accept-Language' => "zh-cn,zh-tw;q=0.7, en-us,*;q=0.3",
    );
    while ( my ( $k, $v ) = each %default_headers ) {
        $http->add_header( $k, $v );
    }

    return $http;
} ## end sub init_browser

sub request_url {
    my ( $self, $url, $post_data ) = @_;

    my $response;
    for my $i ( 1 .. $self->{retry} ) {
        $response = $self->make_request( $url, $post_data );
        next unless ($response);

        return $self->decode_response_content($response);
    } ## end for my $i ( 1 .. $self->...)

    return;
} ## end sub get_url_ref

sub make_request {
    my ( $self, $url, $post_data ) = @_;

    if ($post_data) {
        $self->{browser}->post( $url, $post_data );
    }
    else {
        $self->{browser}->get($url);
    }

    return unless ( $self->{browser}->success() );
    return $self->{browser}->response();
}

sub decode_response_content {
    my ( $self, $response ) = @_;

    my $html = $response->decoded_content( charset => 'none' );
    my $charset = detect($html);
    $html = decode( $charset, $html, Encode::FB_XMLCREF );
    return \$html;
}

no Moo;
1;
