#!/home/isucon/local/perl-5.18/bin/perl
use strict;
use warnings;
use lib '/home/isucon/webapp/perl/local/lib/perl5';

`cat /home/isucon/webapp/config/add-schema.sql | mysql -uisucon isucon`;
