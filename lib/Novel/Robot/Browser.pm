# ABSTRACT: get/post url, return unicode content, auto detect CJK charset
package Novel::Robot::Browser;

use strict;
use warnings;
use utf8;

our $VERSION = 0.15;

use Encode::Detect::CJK qw/detect/;
use Encode;
use HTTP::Tiny;
use Parallel::ForkManager;
use Term::ProgressBar;
use IO::Uncompress::Gunzip qw(gunzip);

our %DEFAULT_HEADER = (
    'Accept' =>
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Charset'  => 'gb2312,utf-8;q=0.7,*;q=0.7',
    'Accept-Encoding' => "gzip",
    'Connection'      => 'keep-alive',
    'User-Agent' =>
      'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0; MALC)',
    'Accept-Language' => "zh-cn,zh-tw;q=0.7, en-us,*;q=0.3",
);

sub new {
    my ( $self, %opt ) = @_;
    $opt{retry}           ||= 5;
    $opt{max_process_num} ||= 5;
    $opt{browser}         ||= _init_browser( $opt{browser_headers} );
    bless {%opt}, __PACKAGE__;
}

sub _init_browser {
    my ($headers) = @_;

    $headers ||= {};
    my %h = ( %DEFAULT_HEADER, %$headers );

    my $http = HTTP::Tiny->new( default_headers => \%h, );

    return $http;
} ## end sub init_browser

sub request_urls {
    my ( $self, $arr, %opt ) = @_;

    my $progress;
    $progress = Term::ProgressBar->new( { count => scalar(@$arr) } )
      if ( $opt{show_progress_bar} );
    my $cnt = 0;

    my @res;
    my $pm = Parallel::ForkManager->new( $self->{max_process_num} );
    $pm->run_on_finish(
        sub {
            my ( $pid, $exit_code, $ident, $exit, $core, $data ) = @_;
            $cnt++;
            $progress->update($cnt) if ( $opt{show_progress_bar} );
            return unless ($data);
            my ( $i, $r ) = @$data;
            $res[$i] = $r;
        }
    );

    $opt{request_sub} ||= sub {
        my ($x) = @_;
        my ( $url, $post_var ) =
            exists $opt{url_sub} ? $opt{url_sub}->($x)
          : ref($x) eq 'HASH' ? ( $x->{url}, $x->{post_var} )
          : ref($x) eq 'ARRAY' ? @$x
          :                      ( $x, undef );
        return $self->request_url( $url, $post_var );
    };

    for my $i ( 0 .. $#$arr ) {
        my $pid = $pm->start and next;
        my $x = $arr->[$i];

        my $s = $opt{request_sub}->($x);
        $s = $opt{deal_sub}->( $x, $s ) if ( exists $opt{deal_sub} );

        $pm->finish( 0, [ $i, $s ] );
    }
    $pm->wait_all_children;
    return \@res;
}

sub request_url {
    my ( $self, $url, $form ) = @_;
    return unless($url);

    my $c;
    for my $i ( 1 .. $self->{retry} ) {
        eval { $c = $self->request_url_simple( $url, $form ); };
        last if ($c);
        sleep 2;
    }

    return $c;
}

sub request_url_simple {
    my ( $self, $url, $form ) = @_;

    my $res =
        $form
      ? $self->{browser}->post_form( $url, $form )
      : $self->{browser}->get($url);
    return unless ( $res->{success} );

    my $html;
    my $content = $res->{content};
    if ( $res->{headers}{'content-encoding'} and
         $res->{headers}{'content-encoding'} eq 'gzip' ) {
        gunzip \$content => \$html, MultiStream => 1, Append => 1;
    }

    my $charset = detect( $html || $content );
    my $r = decode( $charset, $html || $content, Encode::FB_XMLCREF );

    return \$r;
}

1;
