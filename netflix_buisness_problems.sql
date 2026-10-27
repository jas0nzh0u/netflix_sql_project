-- Netflix Project
 
DROP TABLE IF EXISTS netflix;
CREATE TABLE netflix
(
    show_id        VARCHAR(6),
    type           VARCHAR(10),
    title          VARCHAR(150),
    director       VARCHAR(208),
    casts          VARCHAR(1000),
    country        VARCHAR(150),
    date_added     VARCHAR(50),
    release_year   INT,
    rating         VARCHAR(10),
    duration       VARCHAR(15),
    listed_in      VARCHAR(100),
    description    VARCHAR(250)
);

-- Check if I have all 8807 rows
SELECT * FROM netflix;

-- Show the types of content
SELECT DISTINCT type FROM netflix;

--Data cleaning
-- The business problems below use three cleaned columns (date_added_dt,
-- duration_value, duration_unit), so run this block before them.
-- DQ-01 to DQ-04 match the table in the README.
-- Blocks that start with BEGIN are meant to be run as one selection:
-- read the check query, then COMMIT or ROLLBACK.
 
-- Back up the raw data before changing anything
-- (IF NOT EXISTS so a re-run does not overwrite it with fixed data)

CREATE TABLE IF NOT EXISTS netflix_backup AS SELECT * FROM netflix;

SELECT (SELECT COUNT(*) FROM netflix) AS live_rows,
		(SELECT COUNT(*) FROM netflix_backup) AS backup_rows

-- Profile the data: Checking the blanks per column

SELECT
	COUNT(*) FILTER (WHERE director IS NULL) AS no_director,
	COUNT(*) FILTER (WHERE casts IS NULL) AS no_casts,
	COUNT(*) FILTER (WHERE country IS NULL) AS no_country,
	COUNT(*) FILTER (WHERE date_added IS NULL) AS no_date_added,
	COUNT(*) FILTER (WHERE rating IS NULL) AS no_rating,
	COUNT(*) FILTER (WHERE duration IS NULL) AS no_duration
FROM netflix;

-- Profile the data: Checking the rating values

SELECT rating, COUNT(*) 
FROM netflix
GROUP BY rating
ORDER BY COUNT(*) DESC;

-- Profile data: Checking the format of the dates

SELECT COUNT(*) AS padded_dates
FROM netflix
WHERE date_added <> TRIM (date_added);

-- Profile data: Checking if there are duplicates

SELECT show_id, COUNT(*)
FROM netflix
GROUP BY show_id
HAVING COUNT(*) > 1;

-- Profile data: Do the split values need trimming? (country, cast, genre, director)

SELECT COUNT(*) AS padded_country_values
FROM (SELECT UNNEST(STRING_TO_ARRAY(country, ',')) AS c FROM netflix) 
WHERE c <> TRIM(c);

-- DQ-01: a runtime is sitting in the rating column (3 rows)
-- Cause: in the source file the runtime landed in the rating field and
-- the duration field was left empty.


SELECT show_id, title, rating, duration
FROM netflix
WHERE rating LIKE '% min';

-- Fix: move the value into duration and set rating to NULL

BEGIN;

UPDATE netflix
SET DURATION = rating,
	rating = NULL
WHERE rating LIKE '%min'
AND duration IS NULL;

-- Check the update 
SELECT show_id, rating, duration
FROM netflix
WHERE show_id IN ('s5542', 's5795', 's5814');

COMMIT;

-- DQ-02: date_added is text with stray leading spaces (88 rows)
-- DQ-03: duration mixes minutes and seasons in one text column
-- Fix: add typed columns next to the raw ones and fill them. The raw
-- columns stay as they are, so you can always compare before and after.
-- Run this after DQ-01, so the 3 fixed rows have a duration to split.
-- IF NOT EXISTS lets you re-run the block without an error.

ALTER TABLE netflix ADD COLUMN IF NOT EXISTS date_added_dt DATE;
ALTER TABLE netflix ADD COLUMN IF NOT EXISTS duration_value INTEGER;
ALTER TABLE netflix ADD COLUMN IF NOT EXISTS DURATION_UNIT TEXT;

-- TRIM removes the stray space; TO_DATE turns 'September 25, 2021' into
-- a real date

UPDATE netflix
SET date_added_dt = TO_DATE(TRIM(date_added), 'Month DD, YYYY')
WHERE date_added IS NOT NULL;

-- '90 min' becomes 90 and 'min'; '2 Seasons' becomes 2 and 'Seasons'

UPDATE netflix
SET duration_value = SPLIT_PART(duration, ' ', 1)::INTEGER,
	duration_unit = SPLIT_PART(duration, ' ', 2)
WHERE duration IS NOT NULL

-- Check results
SELECT COUNT(*) FILTER (WHERE date_added_dt IS NOT NULL)                        AS dates_parsed,
       COUNT(*) FILTER (WHERE date_added IS NOT NULL AND date_added_dt IS NULL) AS dates_failed,
       MIN(date_added_dt) AS earliest,
       MAX(date_added_dt) AS latest
FROM netflix;      

SELECT type, duration_unit, COUNT(*), MIN(duration_value), MAX(duration_value)
FROM netflix
GROUP BY type, duration_unit
ORDER BY type, duration_unit;

-- DQ-04: no primary key, and nothing stopping DQ-01 happening again
-- Fix: add a primary key and a CHECK constraint. The CHECK has to go on
-- after DQ-01 is fixed, otherwise it fails on the 3 bad rows.
-- The DROP ... IF EXISTS lines are only there so you can re-run the block.

ALTER TABLE netflix DROP CONSTRAINT IF EXISTS netflix_pkey;
ALTER TABLE netflix ADD PRIMARY KEY(show_id);

ALTER TABLE netflix DROP CONSTRAINT IF EXISTS chk_rating_not_runtime;
ALTER TABLE netflix ADD CONSTRAINT chk_rating_not_runtime
    CHECK (rating IS NULL OR rating !~ '^[0-9]+ min$');

-- Prove both work. Each statement below should fail with the error shown
-- under it. They are commented out because an error stops a run of the
-- whole file. To try one, remove the leading -- from the statement, run it
-- on its own, read the error, then put the -- back.
 
-- INSERT INTO netflix (show_id, type, title, release_year)
-- VALUES ('s1', 'Movie', 'Duplicate of s1', 2021);
--   ERROR:  duplicate key value violates unique constraint "netflix_pkey"
 
--UPDATE netflix SET rating = '90 min' WHERE show_id = 's1';
--   ERROR:  new row for relation "netflix" violates check constraint "chk_rating_not_runtime"
      

-- Problem and Answer
-- 1. Percentage of Movies vs TV Shows	

SELECT type,
    COUNT(*) AS total_content,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM netflix
GROUP BY type;

-- 69.6% movies, 30.4% TV shows

-- 2. Most common rating in each of the top 5 countries	

WITH exploded AS (
	SELECT show_id,
	       TRIM(UNNEST(STRING_TO_ARRAY(country, ','))) AS country,
	       rating
	FROM netflix
	WHERE rating IS NOT NULL
),

top_countries AS (
	SELECT country 
	FROM exploded
	WHERE country <> ''
	GROUP BY country
	ORDER BY count(*) DESC
	LIMIT 5
),

ranked AS (
	SELECT e.country, e.rating, COUNT(*) AS total,
	RANK() OVER (PARTITION BY e.country ORDER BY COUNT(*) DESC ) AS rnk 
	FROM exploded e
	JOIN top_countries t ON t.country = e.country
	GROUP BY e.country, e.rating
)

SELECT country, rating, total
FROM ranked
WHERE rnk = 1
ORDER BY total DESC;

-- TV-MA in the US, UK, France and Canada; TV-14 in India

-- 3. Find the top 5 countries with the most content on Netflix

WITH exploded AS (
	SELECT TRIM(UNNEST(STRING_TO_ARRAY(country, ','))) AS country
	FROM netflix
)

SELECT country, COUNT(*) as total
FROM exploded
GROUP BY country
ORDER BY total DESC
LIMIT 5;

-- United States 3690, India 1046, United Kingdom 806, Canada 445, France 393

-- 4. Shortest movie and the TV show with most seasons	

(SELECT type, title, duration_value, duration unit FROM netflix
WHERE type = 'Movie'
ORDER BY duration_value ASC
LIMIT 1)

UNION ALL

(SELECT type, title, duration_value, duration unit FROM netflix
WHERE type = 'TV Show'
ORDER BY duration_value DESC
LIMIT 1)

-- Silent (3 min); Grey's Anatomy (17 seasons)

-- 5. Month with the most titles added	

SELECT	TO_CHAR(date_added_dt, 'FMMonth') AS month_name,
		COUNT(*)						  AS titles_added
		FROM netflix
		WHERE date_added_dt IS NOT NULL
		GROUP BY 1
		ORDER BY titles_added DESC;


-- July (827), February is lowest (563)

-- 6. Every title from the 5 directors with the most titles	
-- Split the comma-separated directors

WITH directors AS (
    SELECT show_id, TRIM(UNNEST(STRING_TO_ARRAY(director, ','))) AS director
    FROM netflix
    WHERE director IS NOT NULL
),
top_directors AS (
    SELECT director, COUNT(*) AS titles
    FROM directors
    GROUP BY director
    ORDER BY titles DESC
    LIMIT 5
)
SELECT t.director, t.titles, n.title, n.type, n.release_year
FROM top_directors t
JOIN directors d ON d.director = t.director
JOIN netflix n   ON n.show_id = d.show_id
ORDER BY t.titles DESC, t.director, n.release_year, n.title;




-- Rajiv Chilaka 22, Jan Suter 21, Raúl Campos 19, Marcus Raboy 16, Suhas Kadav 16

-- 7. Find the average movie length in minutes for each release decade

SELECT (release_year / 10) * 10 		AS decade,
		COUNT(*)						AS movies,
		ROUND(AVG(duration_value), 1) 	AS avg_minutes 
FROM netflix
WHERE type = 'Movie'
GROUP BY 1
ORDER BY 1;

-- 2000s 112.1 min, 2010s 96.9 min, 2020s 93.6 min

-- 8. Find the average number of years between release year and the year added to Netflix, for movies vs TV shows

SELECT type,
       COUNT(*) AS titles,
       ROUND(AVG(EXTRACT(YEAR FROM date_added_dt)::NUMERIC - release_year), 1) AS avg_years_gap
FROM netflix
WHERE date_added_dt IS NOT NULL
GROUP BY type;

-- Movie 5.7 years, TV Show 2.3 years

-- 9. Find the pair of actors who appear together in the most titles
-- Self-join on the split cast list. a.actor < b.actor keeps each pair
-- once instead of twice.

WITH cast_list AS (
    SELECT show_id, TRIM(UNNEST(STRING_TO_ARRAY(casts, ','))) AS actor
    FROM netflix
    WHERE casts IS NOT NULL
)
SELECT a.actor AS actor_1,
       b.actor AS actor_2,
       COUNT(*) AS titles_together
FROM cast_list a
JOIN cast_list b ON b.show_id = a.show_id AND a.actor < b.actor
WHERE a.actor <> '' AND b.actor <> ''
GROUP BY a.actor, b.actor
ORDER BY titles_together DESC, actor_1, actor_2
LIMIT 10;
-- Julie Tejwani and Rupa Bhimani, 31 titles

-- 10. Find how many titles were added to Netflix each year
-- 2021 is a partial year: the data stops on 25 September. The 10 titles
-- with no date_added are left out.
 
SELECT EXTRACT(YEAR FROM date_added_dt)::INT AS year_added,
       COUNT(*)                              AS titles_added
FROM netflix
WHERE date_added_dt IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Peak in 2019 with 2,016 titles; 2015 had 82 and 2021 has 1,498 so far