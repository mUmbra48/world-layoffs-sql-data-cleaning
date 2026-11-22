-- =====================================================================
-- WORLD LAYOFFS: DATA CLEANING IN MYSQL
-- =====================================================================
-- Goal    : Turn the raw layoffs table into a clean table that is ready
--           for analysis, without ever changing the original data.
-- Dataset : https://www.kaggle.com/datasets/swaptr/layoffs-2022
-- Tools   : MySQL 8.0, MySQL Workbench
-- Source  : Based on the "Data Cleaning in MySQL | Full Project" tutorial
--           by Alex The Analyst (YouTube). Checks, comments and the order
--           of some steps were adapted for this write-up.
-- Run     : Top to bottom. The script can be re-run: the staging tables
--           are dropped and rebuilt, and the raw table `layoffs` is
--           never modified.
-- Needs   : The raw data already imported into world_layoffs.layoffs
--           (Workbench: Table Data Import Wizard).
--
-- Stages  : 0. Staging table (safety copy)
--           1. Remove duplicates
--           2. Standardize the data
--           3. Review NULL values
--           4. Remove rows and columns that are not needed
-- =====================================================================

USE world_layoffs;

-- Workbench's "safe update mode" blocks UPDATE / DELETE statements that do
-- not filter on a key column (Error 1175). Most statements below do not,
-- so it is switched off. This only lasts for the current session.
SET SQL_SAFE_UPDATES = 0;


-- =====================================================================
-- STEP 0: STAGING TABLE
-- All cleaning happens in a copy, so the raw data is never at risk.
-- =====================================================================

-- Look at the raw data first.
SELECT * FROM layoffs LIMIT 20;

DROP TABLE IF EXISTS layoffs_staging;

-- Same structure (columns, types), no rows.
CREATE TABLE layoffs_staging LIKE layoffs;

-- Fill the copy. Run this once: running it twice doubles every row.
INSERT INTO layoffs_staging
SELECT * FROM layoffs;

-- Check: the two counts must be equal.
SELECT (SELECT COUNT(*) FROM layoffs)         AS raw_rows,
       (SELECT COUNT(*) FROM layoffs_staging) AS staging_rows;


-- =====================================================================
-- STEP 1: REMOVE DUPLICATES
-- A row is a duplicate only if ALL columns match another row.
-- ROW_NUMBER() numbers the rows inside each group of identical rows:
-- the first copy gets 1, the extra copies get 2, 3, ...
-- =====================================================================

-- 1a. Trim stray spaces from company names first, so that a hidden space
--     cannot make two identical rows look different.
UPDATE layoffs_staging
SET company = TRIM(company);

-- 1b. First attempt: compare only 4 columns.
--     (WHERE cannot see a window function result, so it is wrapped in a
--     subquery and filtered from the outside.)
SELECT *
FROM (
    SELECT company, industry, total_laid_off, `date`,
           ROW_NUMBER() OVER (
               PARTITION BY company, industry, total_laid_off, `date`
           ) AS row_num
    FROM layoffs_staging
) AS duplicates
WHERE row_num > 1;

-- 1c. Check one company from the result. Oda's rows are legitimate: they
--     match on those 4 columns but differ in other columns, so 4 columns
--     is too loose and would delete real data.
SELECT *
FROM layoffs_staging
WHERE company = 'Oda';

-- 1d. The real check: compare all 9 columns.
SELECT *
FROM (
    SELECT company, location, industry, total_laid_off, percentage_laid_off,
           `date`, stage, country, funds_raised_millions,
           ROW_NUMBER() OVER (
               PARTITION BY company, location, industry, total_laid_off,
                            percentage_laid_off, `date`, stage, country,
                            funds_raised_millions
           ) AS row_num
    FROM layoffs_staging
) AS duplicates
WHERE row_num > 1;

-- 1e. Two ways of deleting that do NOT work in MySQL (kept as a note).
--     Left commented out, because running them only produces errors.
/*
-- Attempt A: a CTE is a temporary result, not a table, so there is
-- nothing to delete from.
WITH delete_cte AS (
    SELECT <the 9 columns>,
           ROW_NUMBER() OVER (PARTITION BY <the 9 columns>) AS row_num
    FROM layoffs_staging
)
DELETE FROM delete_cte
WHERE row_num > 1;

-- Attempt B: row_num exists only inside the CTE. It is not a column of
-- layoffs_staging, so the DELETE cannot use it.
WITH delete_cte AS (
    SELECT <the 9 columns>,
           ROW_NUMBER() OVER (PARTITION BY <the 9 columns>) AS row_num
    FROM layoffs_staging
)
DELETE FROM layoffs_staging
WHERE (<the 9 columns>, row_num) IN (
    SELECT <the 9 columns>, row_num FROM delete_cte
) AND row_num > 1;
*/

-- 1f. The working solution: store the row number in a real column of a
--     second staging table, then delete using that column.
DROP TABLE IF EXISTS layoffs_staging2;

CREATE TABLE layoffs_staging2 LIKE layoffs_staging;

ALTER TABLE layoffs_staging2 ADD COLUMN row_num INT;

INSERT INTO layoffs_staging2
    (company, location, industry, total_laid_off, percentage_laid_off,
     `date`, stage, country, funds_raised_millions, row_num)
SELECT company, location, industry, total_laid_off, percentage_laid_off,
       `date`, stage, country, funds_raised_millions,
       ROW_NUMBER() OVER (
           PARTITION BY company, location, industry, total_laid_off,
                        percentage_laid_off, `date`, stage, country,
                        funds_raised_millions
       ) AS row_num
FROM layoffs_staging;

-- Keep the first copy of each row (row_num = 1), delete the extra
-- copies (row_num >= 2).
DELETE FROM layoffs_staging2
WHERE row_num >= 2;

-- Check: how many duplicate rows were removed.
SELECT (SELECT COUNT(*) FROM layoffs_staging)  AS before_dedup,
       (SELECT COUNT(*) FROM layoffs_staging2) AS after_dedup;


-- =====================================================================
-- STEP 2: STANDARDIZE THE DATA
-- Make the same thing look the same everywhere. From here on, all work
-- is done in layoffs_staging2.
-- =====================================================================

-- 2a. Industry: missing values.
--     A missing industry is either NULL or an empty string ''.
SELECT DISTINCT industry
FROM layoffs_staging2
ORDER BY industry;

SELECT *
FROM layoffs_staging2
WHERE industry IS NULL
   OR industry = ''
ORDER BY industry;

-- Example: Airbnb has an industry on one row and a blank on another.
SELECT *
FROM layoffs_staging2
WHERE company LIKE 'Airbnb%';

-- Turn blanks into NULLs, so there is only one kind of "missing".
UPDATE layoffs_staging2
SET industry = NULL
WHERE industry = '';

-- Fill each NULL industry from another row of the same company
-- (self join: the same table appears twice as t1 and t2).
UPDATE layoffs_staging2 AS t1
JOIN layoffs_staging2 AS t2
    ON t1.company = t2.company
SET t1.industry = t2.industry
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;

-- Check: only companies with no other row to copy from remain (Bally's).
SELECT *
FROM layoffs_staging2
WHERE industry IS NULL
   OR industry = ''
ORDER BY industry;

-- 2b. Industry: spelling variants of Crypto.
UPDATE layoffs_staging2
SET industry = 'Crypto'
WHERE industry IN ('Crypto Currency', 'CryptoCurrency');

SELECT DISTINCT industry
FROM layoffs_staging2
ORDER BY industry;

-- 2c. Country: "United States" and "United States." (trailing period).
SELECT DISTINCT country
FROM layoffs_staging2
ORDER BY country;

UPDATE layoffs_staging2
SET country = TRIM(TRAILING '.' FROM country);

SELECT DISTINCT country
FROM layoffs_staging2
ORDER BY country;

-- 2d. Date: convert text such as '12/16/2022' into a real DATE.
--     Preview first, then update, then change the column type.
SELECT `date`,
       STR_TO_DATE(`date`, '%m/%d/%Y') AS converted
FROM layoffs_staging2;

UPDATE layoffs_staging2
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y');

ALTER TABLE layoffs_staging2
MODIFY COLUMN `date` DATE;

-- Check: the Type of `date` must now be 'date', not 'text'.
DESCRIBE layoffs_staging2;


-- =====================================================================
-- STEP 3: REVIEW NULL VALUES
-- No changes here, only a decision. NULL means "unknown". Replacing it
-- with 0 would claim the value is known, and it would drag averages
-- down, because SUM / AVG / COUNT(column) ignore NULLs.
-- =====================================================================

SELECT SUM(total_laid_off IS NULL)        AS null_total_laid_off,
       SUM(percentage_laid_off IS NULL)   AS null_percentage_laid_off,
       SUM(funds_raised_millions IS NULL) AS null_funds_raised,
       SUM(industry IS NULL)              AS null_industry
FROM layoffs_staging2;


-- =====================================================================
-- STEP 4: REMOVE ROWS AND COLUMNS THAT ARE NOT NEEDED
-- =====================================================================

-- Rows with neither a number nor a percentage of layoffs carry no
-- layoff information. Look at them first, then delete.
SELECT *
FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

DELETE FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

-- The helper column was only needed to find duplicates.
ALTER TABLE layoffs_staging2
DROP COLUMN row_num;


-- =====================================================================
-- FINAL CHECKS
-- =====================================================================

-- No duplicates left (expect 0 rows).
SELECT company, location, industry, total_laid_off, percentage_laid_off,
       `date`, stage, country, funds_raised_millions,
       COUNT(*) AS copies
FROM layoffs_staging2
GROUP BY company, location, industry, total_laid_off, percentage_laid_off,
         `date`, stage, country, funds_raised_millions
HAVING COUNT(*) > 1;

-- Raw rows versus clean rows.
SELECT (SELECT COUNT(*) FROM layoffs)          AS raw_rows,
       (SELECT COUNT(*) FROM layoffs_staging2) AS clean_rows;

-- The clean table, ready for exploratory analysis.
SELECT *
FROM layoffs_staging2;
