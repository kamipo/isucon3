use strict;
use warnings;
use Test::More;
use File::Basename;
use Plack::Builder;
use Plack::Test;
use HTTP::Request::Common;

use Isucon3::Web;

my $root_dir = File::Basename::dirname(__FILE__) . "/..";
my $app = Isucon3::Web->psgi($root_dir);

subtest "/" => sub {
    test_psgi
        app    => $app,
        client => sub {
            my $cb  = shift;
            my $res = $cb->( GET "http://localhost/" );
            is $res->code, 200 or die $res->content;
            ok $res->content, "content";
        };
};
done_testing;
