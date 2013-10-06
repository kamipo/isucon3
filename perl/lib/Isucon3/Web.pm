package Isucon3::Web;

use strict;
use warnings;
use utf8;
use Kossy;
use JSON qw/ decode_json /;
use Digest::SHA qw/ sha256_hex /;
use DBIx::Sunny;
use File::Temp qw/ tempfile /;
use IO::Handle;
use Encode;
use Time::Piece;
use Cache::Memcached::Fast;

my $DO_NOT_EXPIRE = 10 * 60; # 10 min

my $KEY_MEMOS_COUNT = 'memos_count';;

sub load_config {
    my $self = shift;
    $self->{_config} ||= do {
        my $env = $ENV{ISUCON_ENV} || 'local';
        open(my $fh, '<', $self->root_dir . "/../config/${env}.json") or die $!;
        my $json = do { local $/; <$fh> };
        close($fh);
        decode_json($json);
    };
}

sub memd {
    my($self) = @_;
    $self->{_memd} ||= do {
        my $memd_port = $ENV{MEMD_PORT} || '11211';
        Cache::Memcached::Fast->new({
            servers => [ "localhost:$memd_port" ],
        });
    };
}

sub cache {
    my($self, $key, $expires_in, $cb) = @_;

    my $value = $self->memd->get($key);
    unless (defined $value) {
        $value = $cb->($key);
        $self->memd->set($key, $value, $expires_in);
    }
    return $value;
}

sub markdown {
    my($self, $content) = @_;
    my $bytes = encode_utf8($content);
    my $key   = 'markdown:' . sha256_hex($bytes);

    return $self->cache($key, $DO_NOT_EXPIRE, sub {
        my ($fh, $filename) = tempfile();
        $fh->print($bytes);
        $fh->close;
        my $html = qx{ ../bin/markdown $filename };
        unlink $filename;
        return $html;
    });
}

sub incr_memos_count {
    my($self) = @_;

    $self->memd->delete($KEY_MEMOS_COUNT);
    return;
}

sub get_memos_count {
    my($self) = @_;

    return $self->cache($KEY_MEMOS_COUNT, $DO_NOT_EXPIRE, sub {
        $self->dbh->select_one(
            'SELECT count(*) FROM public_memos'
        );
    });
}

sub dbh {
    my ($self) = @_;
    $self->{_dbh} ||= do {
        my $dbconf = $self->load_config->{database};
        DBIx::Sunny->connect(
            "dbi:mysql:database=${$dbconf}{dbname};host=${$dbconf}{host};port=${$dbconf}{port}", $dbconf->{username}, $dbconf->{password}, {
                RaiseError => 1,
                PrintError => 0,
                AutoInactiveDestroy => 1,
                mysql_enable_utf8   => 1,
                mysql_auto_reconnect => 1,
            },
        );
    };
}

sub set_username_into_memos {
    my($self, $memos) = @_;

    my %user2memo;
    for my $memo (@$memos) {
        $user2memo{$memo->{user}} ||= [];
        push @{ $user2memo{$memo->{user}} }, $memo;
    }

    # TODO: memcached で lookup_multi して取ってくる
    my @user_id_list = sort keys %user2memo;
    my $users = $self->dbh->select_all(
        'SELECT id, username FROM users WHERE id IN (?)', \@user_id_list
    );
    for my $user (@$users) {
        for my $memo (@{ $user2memo{$user->{id}} }) {
            $memo->{username} = $user->{username};
        }
    }
}

sub userid_key {
    my(undef, $id) = @_;
    "userid:$id";
}
sub username_key {
    my(undef, $id) = @_;
    "username:$id";
}

sub get_user {
    my($self, $by, $key) = @_;
    if ($by eq 'id') {
        my $cache_key = $self->userid_key($key);
        my $data = $self->memd->get($cache_key);
        unless ($data) {
            my $user = $self->dbh->select_row(
                'SELECT username, password, salt FROM users WHERE id=?',
                $key,
            );
            return unless $user;
            $data = join "\t", $user->{username}, $user->{password}, $user->{salt};
            $self->memd->set($cache_key, $data);
        }
        my @datas = split /\t/, $data;
        return +{
            id       => $key,
            username => $datas[0],
            password => $datas[1],
            salt     => $datas[2],
        };
    } elsif ($by eq 'name') {
        my $cache_key = $self->username_key($key);
        my $data = $self->memd->get($cache_key);
        unless ($data) {
            my $user = $self->dbh->select_row(
                'SELECT id, password, salt FROM users WHERE username=?',
                $key,
            );
            return unless $user;
            $data = join "\t", $user->{id}, $user->{password}, $user->{salt};
            $self->memd->set($cache_key, $data);
        }
        my @datas = split /\t/, $data;
        return +{
            id       => $datas[0],
            username => $key,
            password => $datas[1],
            salt     => $datas[2],
        };
    }
}

filter 'session' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        my $sid = $c->req->env->{"psgix.session.options"}->{id};
        $c->stash->{session_id} = $sid;
        $c->stash->{session}    = $c->req->env->{"psgix.session"};
        $app->($self, $c);
    };
};

filter 'get_user' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;

        my $user_id = $c->req->env->{"psgix.session"}->{user_id};
        my $user = $user_id ? $self->get_user( id => $user_id ) : undef;
        $c->stash->{user} = $user;
        $c->res->header('Cache-Control', 'private') if $user;
        $app->($self, $c);
    }
};

filter 'require_user' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        unless ( $c->stash->{user} ) {
            return $c->redirect('/');
        }
        $app->($self, $c);
    };
};

filter 'anti_csrf' => sub {
    my ($app) = @_;
    sub {
        my ($self, $c) = @_;
        my $sid   = $c->req->param('sid');
        my $token = $c->req->env->{"psgix.session"}->{token};
        if ( $sid ne $token ) {
            return $c->halt(400);
        }
        $app->($self, $c);
    };
};

get '/' => [qw(session get_user)] => sub {
    my ($self, $c) = @_;

    my $total = $self->get_memos_count();
    my $memos = $self->dbh->select_all(
        'SELECT * FROM public_memos JOIN memos ON public_memos.memo_id=memos.id ORDER BY public_memos.id DESC LIMIT 100',
    );
    $self->set_username_into_memos($memos);
    $c->render('index.tx', {
        memos => $memos,
        page  => 0,
        total => $total,
    });
};

get '/recent/:page' => [qw(session get_user)] => sub {
    my ($self, $c) = @_;
    my $page  = int $c->args->{page};
    my $total = $self->get_memos_count();
    my $memos = $self->dbh->select_all(
        sprintf("SELECT memos.id AS id, user, content, is_private, created_at, updated_at FROM public_memos JOIN memos ON public_memos.memo_id=memos.id ORDER BY public_memos.id DESC LIMIT 100 OFFSET %d", $page * 100)
    );
    if ( @$memos == 0 ) {
        return $c->halt(404);
    }

    $self->set_username_into_memos($memos);
    $c->render('index.tx', {
        memos => $memos,
        page  => $page,
        total => $total,
    });
};

get '/signin' => [qw(session get_user)] => sub {
    my ($self, $c) = @_;
    $c->render('signin.tx', {});
};

post '/signout' => [qw(session get_user require_user anti_csrf)] => sub {
    my ($self, $c) = @_;
    $c->req->env->{"psgix.session.options"}->{change_id} = 1;
    delete $c->req->env->{"psgix.session"}->{user_id};
    $c->redirect('/');
};

post '/signup' => [qw(session anti_csrf)] => sub {
    my ($self, $c) = @_;

    my $username = $c->req->param("username");
    my $password = $c->req->param("password");
    my $user = $self->get_user( name => $username );
    if ($user) {
        $c->halt(400);
    }
    else {
        my $salt = substr( sha256_hex( time() . $username ), 0, 8 );
        my $password_hash = sha256_hex( $salt, $password );
        $self->dbh->query(
            'INSERT INTO users (username, password, salt) VALUES (?, ?, ?)',
            $username, $password_hash, $salt,
        );
        my $user_id = $self->dbh->last_insert_id;

        # set cache
        $self->memd->set($self->userid_key($user_id), join("\t", $username, $password_hash, $salt));
        $self->memd->set($self->username_key($username), join("\t", $user_id, $password_hash, $salt));

        $c->req->env->{"psgix.session"}->{user_id} = $user_id;
        $c->redirect('/mypage');
    }
};

post '/signin' => [qw(session)] => sub {
    my ($self, $c) = @_;

    my $username = $c->req->param("username");
    my $password = $c->req->param("password");
    my $user = $self->get_user( name => $username );
    if ( $user && $user->{password} eq sha256_hex($user->{salt} . $password) ) {
        $c->req->env->{"psgix.session.options"}->{change_id} = 1;
        my $session = $c->req->env->{"psgix.session"};
        $session->{user_id} = $user->{id};
        $session->{token}   = sha256_hex(rand());
        $self->dbh->query(
            'UPDATE users SET last_access=now() WHERE id=?',
            $user->{id},
        );
        return $c->redirect('/mypage');
    }
    else {
        $c->render('signin.tx', {});
    }
};

get '/mypage' => [qw(session get_user require_user)] => sub {
    my ($self, $c) = @_;

    my $memos = $self->dbh->select_all(
        'SELECT id, content, is_private, created_at, updated_at FROM memos WHERE user=? ORDER BY created_at DESC',
        $c->stash->{user}->{id},
    );
    $c->render('mypage.tx', { memos => $memos });
};

post '/memo' => [qw(session get_user require_user anti_csrf)] => sub {
    my ($self, $c) = @_;

    my $is_private = scalar($c->req->param('is_private')) ? 1 : 0;

    $self->dbh->query(
        'INSERT INTO memos (user, content, is_private, created_at) VALUES (?, ?, ?, now())',
        $c->stash->{user}->{id},
        scalar $c->req->param('content'),
        $is_private,
    );
    unless ($is_private) {
        $self->incr_memos_count();
    }
    my $memo_id = $self->dbh->last_insert_id;
    $c->redirect('/memo/' . $memo_id);
};

get '/memo/:id' => [qw(session get_user)] => sub {
    my ($self, $c) = @_;

    my $user = $c->stash->{user};
    my $memo = $self->dbh->select_row(
        'SELECT id, user, content, is_private, created_at, updated_at FROM memos WHERE id=?',
        $c->args->{id},
    );
    unless ($memo) {
        $c->halt(404);
    }
    if ($memo->{is_private}) {
        if ( !$user || $user->{id} != $memo->{user} ) {
            $c->halt(404);
        }
    }
    $memo->{content_html} = $self->markdown($memo->{content});
    $memo->{username} = $self->get_user( id => $memo->{user} )->{username};

    # そのユーザの前後のメモのIDを取る
    my ($newer, $older);
    my $id = $c->args->{id};
    if ($user && $user->{id} == $memo->{user}) {
        my $memos = $self->dbh->select_all(
            '(SELECT id FROM memos WHERE user=? AND id > ? ORDER BY id LIMIT 1) UNION (SELECT id FROM memos WHERE user=? AND id < ? ORDER BY id DESC LIMIT 1)',
            $memo->{user},
            $id,
            $memo->{user},
            $id,
        );
        ($newer, $older) = @$memos;
    }
    else {
        my $memos = $self->dbh->select_all(
            '(SELECT memo_id AS id FROM public_memos WHERE user=? AND memo_id > ? ORDER BY memo_id LIMIT 1) UNION (SELECT memo_id AS id FROM public_memos WHERE user=? AND memo_id < ? ORDER BY memo_id DESC LIMIT 1)',
            $memo->{user},
            $id,
            $memo->{user},
            $id,
        );
        ($newer, $older) = @$memos;
    }
    if ($id > $newer->{id}) {
        ($older, $newer) = ($newer, $older);
    }

    $c->render('memo.tx', {
        memo  => $memo,
        older => $older,
        newer => $newer,
    });
};

1;
