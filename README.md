# World Layoffs: Data Cleaning in MySQL

Cleaning a raw, real-world layoffs dataset with SQL, so it is ready for analysis. The original data is never modified: every change is made in a copy.

**Author:** Dr. Abdulrahman Saad Abdulwahed Al Allawy  \|  [LinkedIn ](https://www.linkedin.com/in/abdulrahman-al-alallawy-06b8a7284/) \|  [GitHub](https://github.com/](https://github.com/mUmbra48)

## Overview

The raw table contains company layoffs with the company, location, industry, number and percentage laid off, date, funding stage, country and funds raised. Like most real data, it has duplicate rows, blank and missing values, inconsistent spellings and dates stored as text. This project finds and fixes those problems step by step and checks each fix with a query.

## Dataset

[Layoffs 2022 on Kaggle](https://www.kaggle.com/datasets/swaptr/layoffs-2022). Check the dataset's license on Kaggle before re-sharing the CSV. The raw file is not included in this repository.

## Tools

- MySQL 8.0
- MySQL Workbench

## What the script does

| Stage | What is done | SQL used |
| --- | --- | --- |
| 0. Staging | Copy the raw table into `layoffs_staging`, so the original is never at risk | `CREATE TABLE ... LIKE`, `INSERT ... SELECT` |
| 1. Duplicates | Find rows that match on all 9 columns and delete the extra copies | `ROW_NUMBER() OVER (PARTITION BY ...)`, subquery, `DELETE` |
| 2. Standardize | Fill missing industries from other rows of the same company, merge the "Crypto" spelling variants, remove a trailing period from the country, convert the date text into a real `DATE` | self join `UPDATE`, `TRIM`, `STR_TO_DATE`, `ALTER TABLE` |
| 3. NULL values | Review the NULLs and decide to keep them as "unknown" | `SUM(column IS NULL)` |
| 4. Clean-up | Delete rows with no layoff data, drop the helper column | `DELETE`, `DROP COLUMN` |

The three tables, and their roles:

| Table | Role |
| --- | --- |
| `layoffs` | The raw data. Never changed. |
| `layoffs_staging` | An exact copy of the raw data, used to test the duplicate check. |
| `layoffs_staging2` | The working table. At the end it is the clean result. |

## Key decisions and lessons

- **Compare all columns when looking for duplicates.** A first check on 4 columns flagged legitimate rows (for example the company Oda). Comparing all 9 columns finds only true duplicates.
- **Window functions cannot be filtered in** **`WHERE`.** The `ROW_NUMBER()` query is wrapped in a subquery, and the outer query filters on `row_num`.
- **A CTE cannot be deleted from in MySQL.** Two `DELETE ... WITH` attempts fail, and are kept (commented out) in the script as a note. The working solution stores the row number in a real column in `layoffs_staging2` and deletes using that column.
- **Blanks became NULL before filling.** Empty text `''` and `NULL` both mean "missing". Converting blanks to NULL leaves one kind of missing value to handle.
- **NULLs in the numeric columns were kept.** NULL means "unknown". Replacing it with 0 would make `AVG` and `SUM` wrong in the analysis phase.
- **Rows with neither** **`total_laid_off`** **nor** **`percentage_laid_off`** **were deleted.** They carry no layoff information. This is a judgment call, and it is safe because the raw `layoffs` table is untouched.
- **Check after every change.** Almost every `UPDATE` is followed by a `SELECT` that proves it worked, and the script ends with final checks (no duplicates, row counts).

## Results

Run the count queries at the end of the script and fill in your numbers:

|  | Rows |
| --- | --- |
| Raw table (`layoffs`) | *2361* |
| After removing duplicates | *2356* |
| Clean table (`layoffs_staging2`) | *1995* |

## How to run

1. Create the schema: `CREATE DATABASE world_layoffs;`
2. Import the Kaggle CSV into a table named `layoffs` (Workbench: right-click the schema, Table Data Import Wizard).
3. Open [`sql/data_cleaning.sql`](sql/data_cleaning.sql) and run it top to bottom.

The script can be re-run: the staging tables are dropped and rebuilt each time.

## Repository structure

```
.
├── README.md
├── sql/
│   └── data_cleaning.sql      # the full cleaning script
└── docs/
    └── World_Layoffs_SQL_Project.pdf   # step-by-step explanation of every block
```

## Credits

Based on the *Data Cleaning in MySQL \| Full Project* tutorial by Alex The Analyst (YouTube). Dataset by [swaptr on Kaggle](https://www.kaggle.com/datasets/swaptr/layoffs-2022).

## Next steps

- Exploratory data analysis on the clean table: top companies by layoffs, layoffs per year and country, a rolling total.
- A dashboard (Power BI or Tableau) built on the clean data.
