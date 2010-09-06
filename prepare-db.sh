#!/bin/sh
# $Id$

DBSCRIPT=db/rss2html.sql

if [ -z $1 ]; then
    echo "Usage: $0 DBFILE"
    exit 1;
fi

DBFILE=$1

if [ -e $DBFILE ]; then
    echo "Database $DBFILE already exists, aborting..."
    exit 1;
fi

sqlite3 $DBFILE < $DBSCRIPT
