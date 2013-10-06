#!/home/isucon/local/perl-5.18/bin/perl
use strict;
use warnings;
use lib '/home/isucon/webapp/perl/lib', '/home/isucon/webapp/perl/local/lib/perl5';

use File::Basename;

use Isucon3::Web;

my $root_dir = File::Basename::dirname(__FILE__);

my $app = Isucon3::Web->new("$root_dir/..");

`cat /home/isucon/webapp/config/add-schema.sql | mysql -uisucon isucon`;

# create user cache
my $users = $app->dbh->select_all('SELECT id, username, password, salt FROM users');
for my $user (@$users) {
    $app->memd->set($app->userid_key($user->{id}), join("\t", $user->{username}, $user->{password}, $user->{salt}));
    $app->memd->set($app->username_key($user->{username}), join("\t", $user->{id}, $user->{password}, $user->{salt}));
}

# memo page data cache
my $memos = $app->dbh->select_all('SELECT id, user, content, is_private, created_at, updated_at FROM memos');
for my $memo (@$memos) {

    $app->get_memo_page($memos->{id}, $app->memd->get($app->userid_key($memos->{user})), 1, $memo);

    #$app->memos_user_key()
}
