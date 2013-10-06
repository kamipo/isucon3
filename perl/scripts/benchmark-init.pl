#!/home/isucon/local/perl-5.18/bin
use strict;
use warnings;
use lib '/home/isucon/webapp/perl/local/lib/perl5';

`cat /home/isucon/webapp/config/schema.sql | mysql -uisucon isucon`;
`echo 'INSERT INTO (memo_id) SELECT id FROM memos ORDER BY id' | mysql -uisucon isucon`;
