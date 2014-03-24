# ABSTRACT: 自动化获取网页内容，并解码为unicode
package Novel::Robot::Browser;

use strict;
use warnings;
use utf8;

our $VERSION = 0.14;

use Encode::Detect::CJK qw/detect/;
use Encode;
use WWW::Mechanize;
use Term::ProgressBar;

sub new {
    my ($self, %opt) = @_;
    $opt{retry} ||= 5;
    $opt{max_process_num} ||=5;
    $opt{browser} ||= _init_browser();
    bless { %opt } , __PACKAGE__;
}

sub _init_browser {
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

#use threads;
#use threads::shared;
#use Thread::Semaphore;
#sub request_urls {
    #my ($self, $arr, %opt) = @_;
    #$opt{request_sub} ||= sub {
        #my ($x) = @_;
        #my ($url, $post_var) = exists $opt{url_sub} ? $opt{url_sub}->($x) : 
        #ref($x) eq 'HASH' ? ( $x->{url}, $x->{post_var} )  :
        #ref($x) eq 'ARRAY' ? @$x : 
        #($x, undef);
        #return $self->request_url($url, $post_var);
    #};

    #my $sem = Thread::Semaphore->new($self->{max_process_num});
    #my $work_func = sub {
        #my ($i) = @_;
        #my $x = $arr->[$i];
        #my $s = $opt{request_sub}->($x);
        #$s = $opt{deal_sub}->($x, $s) if(exists $opt{deal_sub});
        #$sem->up;
        #return [$i, $s ];
    #};
    #my @threads = map {
        #$sem->down;
        #threads->create($work_func, $_);
    #} 0..$#$arr;

    #my @res;
    #for (@threads){
        #my $r = $_->join;
        #$res[$r->[0]] = $r->[1];
    #}
    #return \@res;
#}

#use Coro;
#sub request_urls {
    #my ($self, $arr, %opt) = @_;
    #$opt{request_sub} ||= sub {
        #my ($x) = @_;
        #my ($url, $post_var) = exists $opt{url_sub} ? $opt{url_sub}->($x) : 
        #ref($x) eq 'HASH' ? ( $x->{url}, $x->{post_var} )  :
        #ref($x) eq 'ARRAY' ? @$x : 
        #($x, undef);
        #return $self->request_url($url, $post_var);
    #};

    #my @tasks;
    #my @res;
    #for my $i (0 .. $#$arr){
        #push @tasks, async {
            #my $x = $arr->[$i];
            #my $s = $opt{request_sub}->($x);
            #$s = $opt{deal_sub}->($x, $s) if(exists $opt{deal_sub});
            #$res[$i] = $s;
        #}
    #}
    #for (@tasks){
        #$_->join;
    #}
    #return \@res;
#}

use Parallel::ForkManager;
sub request_urls {
    my ($self, $arr, %opt) = @_;

    my $progress;
    $progress = Term::ProgressBar->new ({ count => scalar(@$arr) }) 
    if($opt{show_progress_bar});
    my $cnt = 0;

    my @res;
    my $pm = Parallel::ForkManager->new( $self->{max_process_num} );
    $pm->run_on_finish(
        sub {
            my ( $pid, $exit_code, $ident, $exit, $core, $data ) = @_;
            $cnt++;
            $progress->update($cnt) if($opt{show_progress_bar});
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

1;
