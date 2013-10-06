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
my $web = Isucon3::Web->new($root_dir);

for my $i(1, 2) {
  my $html = $web->markdown(<<'MD');
# Hello, world!
MD
  is $html, "<h1>Hello, world!</h1>\n", "try $i";
}

done_testing;
