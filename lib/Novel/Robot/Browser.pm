# ABSTRACT: get/post url, return unicode content, auto detect CJK charset
package Novel::Robot::Browser;

use strict;
use warnings;
use utf8;

our $VERSION = 0.19;

use Encode::Detect::CJK qw/detect/;
use Encode;
use HTTP::Tiny;
use Parallel::ForkManager;
use Term::ProgressBar;
use IO::Uncompress::Gunzip qw(gunzip);
use URI::Escape;

our $DEFAULT_URL_CONTENT = '';
our %DEFAULT_HEADER = (
    'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', 
    'Accept-Charset'  => 'gb2312,utf-8;q=0.7,*;q=0.7',
    'Accept-Encoding' => "gzip",
    'Accept-Language' => 'zh,zh-cn;q=0.8,en-us;q=0.5,en;q=0.3', 
    'Connection'      => 'keep-alive',
    'User-Agent' => 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:29.0) Gecko/20100101 Firefox/29.0', 
    'DNT' => 1, 
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

#sub request_urls {
    #my ( $self, $src_arr, %opt ) = @_;
    ## arr : url / { url => .. }
    ## process_sub => sub { my ($html_ref) = @_ ; ... }
    #my $arr = $opt{select_url_sub} ? $opt{select_url_sub}->( $src_arr ) : $src_arr;

    #my $cnt = 0;
    #my %res_hash = ();
    
    #my $iter_sub = sub {
        #my ($r) = @_;
        #return $opt{data_sub}->(@_) if($opt{no_auto_request_url});

        #my ( $url, $post_data ) =
        #ref($r) eq 'HASH' ? @{$r}{qw/url post_data/} 
        #: ( $r, undef );

        #my @procss_data = ($url, $post_data); 
        #if($url=~/^https?:/){
            #my $h = $self->request_url( $url, $post_data );
            #@procss_data = ( \$h );
        #}
        #my @return_data = exists $opt{data_sub} ?
        #$opt{data_sub}->(@procss_data) : @procss_data;
        #return @return_data;
    #};

    #my $progress;
    #$progress = Term::ProgressBar->new( { count => scalar(@$arr) } )
      #if ( $opt{verbose} );


    #my $pm = Parallel::ForkManager->new( $self->{max_process_num} );
    #$pm->run_on_finish(sub {
            #my ( $pid, $exit_code, $ident, $exit, $core, $data ) = @_;

            #$cnt++;
            #$progress->update($cnt) if ( $opt{verbose} );
            #return unless ($data);

            ##my ( $id, @res ) = @$data;
            ##$res_arr[$id] = $#res==0 ? $res[0] : \@res;
            #my ( $i, @res ) = @$data;
            #$res_hash{$i} = $#res==0 ? $res[0] : \@res;
        #});

    #for my $i ( 0 .. $#$arr ) {
        #my $pid = $pm->start and next;
        #my $r = $arr->[$i];
        #my @res = $iter_sub->($r);
        #$pm->finish( 0, [ $i, @res ]);
    #}

    #$pm->wait_all_children;

    #my @res_arr = map { $res_hash{$_} } ( 0 .. $#$arr);
    #return \@res_arr;
#}

sub request_urls {
    my ( $self, $src_arr, %opt ) = @_;
    # arr : url / { url => .. }
    # process_sub => sub { my ($html_ref) = @_ ; ... }
    my $arr = $opt{select_url_sub} ? $opt{select_url_sub}->( $src_arr ) : $src_arr;

    my $cnt = 0;
    my %res_hash = ();

    my $iter_sub = sub {
        my ($r) = @_;
        return $opt{data_sub}->(@_) if($opt{no_auto_request_url});

        my ( $url, $post_data ) =
        ref($r) eq 'HASH' ? @{$r}{qw/url post_data/} 
        : ( $r, undef );

        my @procss_data = ($url, $post_data); 
        if($url=~/^https?:/){
            my $h = $self->request_url( $url, $post_data );
            @procss_data = ( \$h );
        }
        my @return_data = exists $opt{data_sub} ?
        $opt{data_sub}->(@procss_data) : @procss_data;
        return @return_data;
    };

    my $progress;
    $progress = Term::ProgressBar->new( { count => scalar(@$arr) } )
    if ( $opt{verbose} );

    for my $i ( 0 .. $#$arr ) {
        my $r = $arr->[$i];
        my @res = $iter_sub->($r);
        $res_hash{$i} = $#res==0 ? $res[0] : \@res;
        $cnt++;
        $progress->update($cnt) if ( $opt{verbose} );
    }


    my @res_arr = map { $res_hash{$_} } ( 0 .. $#$arr);
    return \@res_arr;
}

sub request_urls_iter {
    my ( $self, $url, %o ) = @_;

    my $html = $self->request_url($url, $o{post_data});

    my $info      = $o{parse_info}->( \$html )      || {};
    my $data_list = $o{parse_content}->( \$html ) || [];

    my $i=1;
    return ( $info, $data_list ) if ( $o{stop_iter} and $o{stop_iter}->( $info, $data_list, $i, %o ) );
    $data_list = [] if($o{min_page_num} and $o{min_page_num}>1);

    my $url_list = $o{get_url_list} ? $o{get_url_list}->( \$html ) : [];
    while(1){
        $i++;
        my $u = $url_list->[$i-2] || ( $o{next_url} ? $o{next_url}->($url, $i, \$html) : undef);
        last unless($u);
        next if($o{min_page_num} and $i<$o{min_page_num});
        last if($o{max_page_num} and $i>$o{max_page_num});

        my ( $u_url, $u_post_data ) = ref($u) eq 'HASH' ? @{$u}{qw/url post_data/} : ( $u, undef );
        my $c = $self->request_url($u_url, $u_post_data);
        my $fs = $o{parse_content}->( \$c ) || [];
        last unless(@$fs);

        push @$data_list, @$fs;
        return ( $info, $data_list ) if ( $o{stop_iter} and $o{stop_iter}->( $info, $data_list, $i, %o ) );
    }

    return ( $info, $data_list );
} 

#sub request_urls_iter {
#    my ( $self, $url, %o ) = @_;
#
#    my $html = $self->request_url($url, $o{post_data});
#
#    my $info      = $o{info_sub}->( \$html )      || {};
#    my $data_list = $o{data_list_sub}->( \$html ) || [];
#
#    return ( $info, $data_list ) if ( $o{stop_sub}->( $info, $data_list ) );
#
#    my $url_list = $o{url_list_sub}->( \$html ) || [];
#    my $select_url_list = $o{select_url_sub}->( $url_list );
#    for my $u (@$select_url_list) {
#        return ( $info, $data_list ) if ( $o{stop_sub}->( $info, $data_list ) );
#
#        my ( $u_url, $u_post_data ) =
#        ref($u) eq 'HASH' ? @{$u}{qw/url post_data/} 
#        : ( $u, undef );
#
#        my $c = $self->request_url($u_url, $u_post_data);
#
#        my $fs = $o{data_list_sub}->( \$c ) || [];
#        push @$data_list, @$fs;
#    }
#
#    return ( $info, $data_list );
#} ## end sub get_tiezi_ref

sub request_url {
    my ( $self, $url, $form ) = @_;
    return $DEFAULT_URL_CONTENT unless($url);

    my $c;
    for my $i ( 1 .. $self->{retry} ) {
        eval { $c = $self->request_url_simple( $url, $form ); };
        last if ($c);
        sleep 2;
    }

    return $c || $DEFAULT_URL_CONTENT;
}

sub format_post_content {
    my ($self, $form) = @_;

    my @params;
    while(my ($k, $v) = each %$form){
        push @params, uri_escape($k)."=".uri_escape($v);
    }

    my $post_str = join("&", @params);
    return $post_str;
}

sub request_url_simple {
    my ( $self, $url, $form ) = @_;

    my $res =
        $form
      ? 
      $self->{browser}->request('POST', $url, {
              content => $self->format_post_content($form),
               headers => { 
                   %DEFAULT_HEADER, 
                   'content-type' => 'application/x-www-form-urlencoded' }, 
          })
      : $self->{browser}->get($url);
    return $DEFAULT_URL_CONTENT unless ( $res->{success} );

    my $html;
    my $content = $res->{content};
    if ( $res->{headers}{'content-encoding'} and
         $res->{headers}{'content-encoding'} eq 'gzip' ) {
        gunzip \$content => \$html, MultiStream => 1, Append => 1;
    }

    my $charset = detect( $html || $content );
    my $r = decode( $charset, $html || $content, Encode::FB_XMLCREF );

    return $r || $DEFAULT_URL_CONTENT;
}

1;
