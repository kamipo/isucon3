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

$ENV{MEMD_PORT} = $memd->option('tcp_port') or die;

my $root_dir = File::Basename::dirname(__FILE__) . "/..";
my $web = Isucon3::Web->new($root_dir);

my $count = 0;

my $value = $web->cache('foo', undef, sub {
    $count++;
    return 42;
});
is $value, 42, 'first time';
is $count, 1, '... count';

$value = $web->cache('foo', undef, sub {
    $count++;
    return 42;
});

is $value, 42, 'second time';
is $count, 1, '... count';

done_testing;
