RSS2HTML
========
This is small set of scripts for generating smartphone-friendly HTML
feeds of your favorite, RSS-enabled web sites.

Getting Started
---------------
1. cd rss2html
2. ./prepare-db.sh db/bar.db
3. ./rss2html.pl -u http://bar.com/rss/feed.xml -t 'Bar' -d db/bar.db -l en -b '#9b2c2a' -o /foo/www/rss2html/docs/bar.html

Running from cron
-----------------
Insert a line like the following in crontab(5):

    */10    *       *       *       *       cd /foo/www/rss2html/; ./rss2html.pl -u http://bar.com/rss/feed.xml -t 'Bar' -d db/bar.db -l en -b '#9b2c2a' -o /foo/www/rss2html/docs/bar.html
