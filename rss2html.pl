#!/usr/bin/perl -w

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
my ($url, $db, $output, $locale, $background);
GetOptions('url|u=s'        => \$url,
		   'db|d=s'         => \$db,
		   'output|o'       => \$output,
		   'locale|l=s'     => \$locale,
		   'background|b=s' => \$background,
		   'help|h'         => sub { usage(); exit });

unless ($url && $db && $locale) {
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
die "GET $url failed: ", $response->status_line unless ($response->is_success);

# Parse RSS
my $rss = XML::RSS->new;
$rss->parse($response->content);

# Prepare DB
my $dbh = DBI->connect("dbi:SQLite:$db") || die "Cannot connect to $db: $DBI::errstr";
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
$template->param(TITLE => $rss->{'channel'}->{'title'});
$template->param(SUBTITLE => $rss->{'channel'}->{'title'});
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
--db, -d           The database filename
--output, -o       The output filename (or - for stdout)
--locale, -l       The locale (e.g. da, en_US, ...)
--background, -b   The title background color (e.g #aa55aa)

--help, -h           Print this help text

EOF
}
