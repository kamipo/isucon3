#!/home/isucon/local/perl-5.18/bin/perl
use strict;
use warnings;
use lib '/home/isucon/webapp/perl/local/lib/perl5';

`cat /home/isucon/webapp/config/add-schema.sql | mysql -uisucon isucon`;
`echo 'INSERT INTO public_memos (memo_id) SELECT id FROM memos ORDER BY id' | mysql -uisucon isucon`;
