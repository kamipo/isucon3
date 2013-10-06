use strict;
use warnings;
use Test::More;
use File::Basename;
use Plack::Builder;
use Plack::Test;
use HTTP::Request::Common;
use Test::Memcached;

use Isucon3::Web;

my $memd = Test::Memcached->new();
$memd->start;

$ENV{MEMD_PORT} = $memd->option('tcp_port');

my $root_dir = File::Basename::dirname(__FILE__) . "/..";
my $app = Isucon3::Web->psgi($root_dir);

subtest "/" => sub {
    test_psgi
        app    => $app,
        client => sub {
            my $cb  = shift;
            my $res = $cb->( GET "http://localhost/" );
            is $res->code, 200, 'first time' or die $res->content;
            ok $res->content, "content";
            
            $res = $cb->( GET "http://localhost/" );
            is $res->code, 200, 'second time' or die $res->content;
            ok $res->content, "content";
        };
};

subtest "/recent/1" => sub {
    test_psgi
        app    => $app,
        client => sub {
            my $cb  = shift;
            my $res = $cb->( GET "http://localhost/recent/1" );
            is $res->code, 200, 'first time' or die $res->content;
            ok $res->content, "content";
            
            $res = $cb->( GET "http://localhost/recent/1" );
            is $res->code, 200, 'second time' or die $res->content;
            ok $res->content, "content";
        };
};
done_testing;
