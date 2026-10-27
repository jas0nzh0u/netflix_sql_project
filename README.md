# Netflix Catalogue Analysis (PostgreSQL)

Clean the Netflix titles dataset with SQL, then answer 10 business questions about it. Everything is in one script: `netflix_business_problems.sql`.

## Dataset

`netflix_titles.csv`: 8,807 titles (6,131 movies and 2,676 TV shows) added to Netflix up to September 2021. Columns: `show_id`, `type`, `title`, `director`, `casts`, `country`, `date_added`, `release_year`, `rating`, `duration`, `listed_in`, `description`.

Source: [Netflix Movies and TV Shows](https://www.kaggle.com/datasets/shivamb/netflix-shows) by shivamb on Kaggle.

## How to run

1. Create a PostgreSQL database (version 11 or newer, for the procedure).
2. Run the `CREATE TABLE` at the top of the script, then import the CSV. The comments under it show the pgAdmin and psql routes.
3. Run the rest of the script top to bottom. Blocks that start with `BEGIN` are meant to be run as one selection and committed once the check query looks right.

## Data cleaning

Profiling the raw table found four faults, labelled DQ-01 to DQ-04 (DQ = data quality issue, numbered in the order the script fixes them). The raw data is backed up first, and the fixes sit under "Data cleaning" in the script.

| ID | Fault | Cause | Fix | Check |
|---|---|---|---|---|
| DQ-01 | 3 rows have a runtime (`74 min`, `84 min`, `66 min`) in the rating column | Runtime landed in the wrong field, duration left empty | `UPDATE` inside a transaction: value moved to `duration`, rating set to NULL because the real rating isn't in the file | No rating matches `% min`; the 3 rows show a duration |
| DQ-02 | `date_added` is text, with a leading space on 88 values | Stored as `September 25, 2021` | New `date_added_dt DATE` column filled with `TRIM` and `TO_DATE` | 8,797 parsed, 0 failed, 2008-01-01 to 2021-09-25 |
| DQ-03 | `duration` mixes `90 min` and `2 Seasons` | One text column for two units | New `duration_value` and `duration_unit` columns | Movies 3 to 312 min, TV shows 1 to 17 seasons |
| DQ-04 | Nothing stopped duplicate IDs or runtimes in the rating column | No primary key or constraints | Primary key on `show_id`, `CHECK` on `rating` | A duplicate insert and a bad update are both rejected |

DQ-02 and DQ-03 are plain `ALTER TABLE` and `UPDATE` statements: they add typed columns and leave the raw ones untouched. An optional section at the end of the cleaning block repeats both fixes as a PL/pgSQL procedure, `refresh_derived_columns()`, which only touches rows that still need changing and logs what it changed in `fix_log`. Running it twice changes nothing the second time.

Left alone on purpose:

- `NR` (80 rows) and `UR` (3 rows) both mean not rated. Merging them is a decision for whoever owns the data.
- 14 titles were added before their release year. Problem 8 keeps them in.
- 2,634 titles have no director and 10 have no `date_added`. Both stay NULL rather than guessed.

## The 10 business problems

| # | Problem | Answer |
|---|---|---|
| 1 | Percentage of Movies vs TV Shows | 69.6% movies, 30.4% TV shows |
| 2 | Most common rating in each of the top 5 countries | TV-MA in the US, UK, France and Canada; TV-14 in India |
| 3 | Top 5 countries with the most content | United States 3,690, India 1,046, United Kingdom 806, Canada 445, France 393 |
| 4 | Shortest movie and the 10 TV shows with most seasons | Silent (3 min); Grey's Anatomy (17 seasons) |
| 5 | Month with the most titles added | July (827); February is lowest (563) |
| 6 | Every title from the 5 directors with the most titles | Rajiv Chilaka 22, Jan Suter 21, Raúl Campos 19, Marcus Raboy 16, Suhas Kadav 16 |
| 7 | Average movie length by release decade | 2000s 112.1 min, 2010s 96.9, 2020s 93.6 |
| 8 | Years between release and being added to Netflix | Movies 5.7, TV shows 2.3 |
| 9 | Pair of actors who appear together most | Julie Tejwani and Rupa Bhimani, 31 titles |
| 10 | Titles added to Netflix each year | Peak of 2,016 in 2019 (82 in 2015); 1,498 in 2021 up to 25 September |

## Skills used

`SELECT`, `INSERT`, `UPDATE` and `DELETE` (the last three practised on a scratch copy and inside transactions with `ROLLBACK`), `ALTER TABLE`, constraints (a primary key and a regex `CHECK`), a PL/pgSQL procedure, CTEs, window functions, `UNNEST` with `STRING_TO_ARRAY`, self-joins, `FILTER`.

## Credits

The layout and the idea come from [najirh/netflix_sql_project](https://github.com/najirh/netflix_sql_project). The 10 problems here are new variations, and the data cleaning is added.
