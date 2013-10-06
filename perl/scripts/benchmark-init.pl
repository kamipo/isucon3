#!/home/isucon/local/perl-5.18/bin/perl
use strict;
use warnings;
use lib '/home/isucon/webapp/perl/lib', '/home/isucon/webapp/perl/local/lib/perl5';

my $root_dir = File::Basename::dirname(__FILE__);

my $app = Isucon3::Web->new("$root_dir/..");

`cat /home/isucon/webapp/config/add-schema.sql | mysql -uisucon isucon`;

# create user cache
my $users = $self->dbh->select_all('SELECT id, username, password, salt FROM user');
for my $user (@$users) {
    $self->memd->set($app->userid_key($user->{id}), join("\t", $user->{username}, $user->{password}, $user->{salt}));
    $self->memd->set($app->username_key($user->{username}), join("\t", $user->{id}, $user->{password}, $user->{salt}));
}
