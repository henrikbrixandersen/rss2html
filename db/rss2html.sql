--DROP TABLE rss2html;
CREATE TABLE rss2html (guid        TEXT PRIMARY KEY,
       	     	       link        TEXT NOT NULL,
       	     	       publishDate DATE NOT NULL,
		       title	   TEXT NOT NULL,
		       text	   TEXT,
		       updated	   BOOLEAN DEFAULT 0);
