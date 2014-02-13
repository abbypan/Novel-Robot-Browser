# ABSTRACT: 自动化获取网页内容，并解码为unicode
package Novel::Robot::Browser;

use strict;
use warnings;
use utf8;

our $VERSION = 0.11;

use Encode::Detect::CJK qw/detect/;
use Encode;
use Moo;
use Parallel::ForkManager;
use WWW::Mechanize;

has retry => ( is => 'rw', default => sub { 5 }, );
has max_process_num => ( is => 'rw', default => sub { 5 }, );

has browser => ( is => 'rw', default => \&init_browser );

sub init_browser {
    my ($self) = @_;
    my $http = WWW::Mechanize->new(
        #onerror => sub { print "fail get url\n"; }, 
        onerror => sub { return; }, 
        stack_depth => 2, 
    );

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

sub request_urls {
    my ($self, $arr, %opt) = @_;

    my @res;
    my $pm = Parallel::ForkManager->new( $self->{max_process_num} );
    $pm->run_on_finish(
        sub {
            my ( $pid, $exit_code, $ident, $exit, $core, $data ) = @_;
            return unless($data);
            my ($i, $r) = @$data;
            $res[$i] = $r;
        }
    );

    $opt{request_sub} ||= sub {
        my ($x) = @_;
        my ($url, $post_var) = exists $opt{url_sub} ? $opt{url_sub}->($x) : 
        ref($x) eq 'HASH' ? ( $x->{url}, $x->{post_var} )  :
        ref($x) eq 'ARRAY' ? @$x : 
        ($x, undef);
        return $self->request_url($url, $post_var);
    };

    for my $i (0 .. $#$arr){
        my $pid = $pm->start and next;
        my $x = $arr->[$i];

        my $s = $opt{request_sub}->($x);
        $s = $opt{deal_sub}->($x, $s) if(exists $opt{deal_sub});

        $pm->finish( 0, [ $i, $s ] );
    }
    $pm->wait_all_children;
    return \@res;
}

sub request_url {
    my ( $self, $url, $post_data ) = @_;

    my $response;
    for my $i ( 1 .. $self->{retry} ) {
        eval { $response = $self->make_request( $url, $post_data ); };
        return $self->decode_response_content($response) if ($response);
        sleep 2;
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
