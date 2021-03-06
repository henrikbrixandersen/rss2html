#!/usr/bin/perl -w
#
# Copyright (c) 2010 - 2012 Henrik Brix Andersen <henrik@brixandersen.dk>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

use strict;

use DBI;
use Date::Parse;
use DateTime;
use Encode;
use Getopt::Long qw/:config bundling/;
use HTML::Template;
use LWP::UserAgent;
use XML::RSS;

# Script arguments
my ($url, $title, $db, $output, $locale, $background);
GetOptions('url|u=s'        => \$url,
		   'title|t=s'      => \$title,
		   'db|d=s'         => \$db,
		   'output|o=s'     => \$output,
		   'locale|l=s'     => \$locale,
		   'background|b=s' => \$background,
		   'help|h'         => sub { usage(); exit });

unless ($url && $title && $db && $locale) {
	usage();
	exit(1);
}

# Static configuration
my $timezone = 'Europe/Copenhagen';
my $hours = 24;
my $encoding = 'utf-8';

# Time format
my $timeformat = '%A, %e %b @ %R';
DateTime->DefaultLocale($locale);

# Fetch RSS
my $browser = LWP::UserAgent->new;
my $response = $browser->get($url);
my $status = $response->is_success ? '' : $response->status_line;

# DB connection
my $dbh = DBI->connect("dbi:SQLite:$db") || die "Cannot connect to $db: $DBI::errstr";

if ($response->is_success) {
	if ($response->content =~ m/<rss /) {
		# Parse RSS
		my $rss = XML::RSS->new;

		eval {
			$rss->parse($response->content);
		};

		unless ($@) {
			# Prepare DB
			my $ch = $dbh->prepare('SELECT publishDate, updated FROM rss2html WHERE guid=?') or die "Couldn't prepare count statement: " . $dbh->errstr;
			my $ih = $dbh->prepare('INSERT INTO rss2html (guid, link, publishDate, title, text) VALUES (?, ?, ?, ?, ?)') or die "Couldn't prepare insert statement: " . $dbh->errstr;
			my $uh = $dbh->prepare('UPDATE rss2html SET link=?, publishDate=?, title=?, text=?, updated=? WHERE guid=?') or die "Couldn't prepare update statement: " . $dbh->errstr;

			# Update DB
			foreach my $item (@{$rss->{'items'}}) {
				my $guid;
				my $link;

				if ($item->{'permaLink'}) {
					$guid = $item->{'permaLink'};
					$link = $item->{'permaLink'};
				} else {
					$guid = $item->{'guid'};
					$link = $item->{'link'};
				}

				my $date = str2time($item->{'pubDate'});
				my $title = $item->{'title'};
				my $text = $item->{'description'};

				$ch->execute($guid);
				my ($olddate, $oldupdated) = $ch->fetchrow_array();

				if ($olddate) {
					my $updated = ($olddate eq $date) ? 0 : 1;
					$uh->execute($link, $date, $title, $text, $oldupdated ? $oldupdated : $updated, $guid) or die "Couldn't update row: " . $dbh->errstr;
				} else {
					$ih->execute($guid, $link, $date, $title, $text) or die "Couldn't insert row: " . $dbh->errstr;
				}
			}

			$ch->finish;
			$ih->finish;
			$uh->finish;

			# Delete rows older than 24 hours
			my $dh = $dbh->prepare('DELETE FROM rss2html WHERE publishDate < ?') or die "Couldn't prepare delete statement: " . $dbh->errstr;
			my $limit = DateTime->now(time_zone => $timezone)->subtract(hours => $hours)->epoch;;
			$dh->execute($limit) or die "Couldn't delete rows: " . $dbh->errstr;
			$dh->finish;
		} else {
			$status = $@;
		}
	} else {
		$status = "Feed is not valid RSS";
	}
}

# Select rows
my $sh = $dbh->prepare('SELECT link, publishDate, updated, title, text FROM rss2html ORDER BY publishDate DESC') or die "Couldn't prepare select statement: " . $dbh->errstr;
$sh->execute() or die "Couldn't select rows: " . $dbh->errstr;

# Format rows
my @item_loop;
while (my $item = $sh->fetchrow_hashref()) {
	my %item_data;
	$item_data{'ITEM_LINK'} = $item->{'link'};
	$item_data{'ITEM_DATE'} = ucfirst encode($encoding, DateTime->from_epoch(epoch => $item->{'publishDate'}, time_zone => $timezone)->strftime($timeformat));
	$item_data{'ITEM_UPDATED'} = $item->{'updated'} ? '*' : '';

	# Strip [tags] at the end of post titles (as used on gizmodo)
	my $title = $item->{'title'};
	$title =~ s/\[([^\]]*)\]$//;
	$item_data{'ITEM_TITLE'} = $title;

	$item_data{'ITEM_TEXT'} = $item->{'text'};
	push(@item_loop, \%item_data);
}
$sh->finish;
$dbh->disconnect;

# Fill in template
my $template = HTML::Template->new(filename => 'templates/rss2html.tmpl');
$template->param(BACKGROUND => "background: $background;") if ($background);
$template->param(ENCODING => $encoding);
$template->param(TITLE => $title);
$template->param(SUBTITLE => $title);
$template->param(STATUS => $status);
$template->param(ITEM_LOOP => \@item_loop);

my $timestamp = encode($encoding, DateTime->now(time_zone => $timezone)->strftime($timeformat));
$template->param(TIMESTAMP => ucfirst $timestamp);
$template->param(COUNT => scalar @item_loop);

if (! $output || $output eq '-') {
	print $template->output;
} else {
	open(OUTPUT, ">$output") or die "Couldn't open $output for writing";
	print OUTPUT $template->output;
	close(OUTPUT);
}

# Usage
sub usage {
	print STDERR <<EOF
Usage: $0 [options]

Options:
--url, -u          The URL of the RSS feed
--title, -t        The title string
--db, -d           The database filename
--output, -o       The output filename (or - for stdout)
--locale, -l       The locale (e.g. da, en_US, ...)
--background, -b   The title background color (e.g #aa55aa)

--help, -h           Print this help text

EOF
}
