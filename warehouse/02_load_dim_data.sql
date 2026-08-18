-- ===========================================================================
-- Load dw.dim_date
-- ===========================================================================
-- The only dimension with no source table — every row is derived from a
-- generated date series rather than loaded from OLTP.
--
-- Range runs 2021-01-01 to 2026-12-31. The lower bound covers the earliest
-- customer signup (2021-08); the upper bound must stay at or beyond the
-- latest order date (2026-08-12), or fact_sales rows for those days would
-- have no date_key to reference and the foreign key would reject them.
--
-- Leap years need no special handling in the series itself: generate_series
-- walks the real calendar, so 2024-02-29 is produced automatically. What a
-- leap year does affect is analysis — 2024 has 366 days, so year-over-year
-- totals are inflated by roughly 0.27% against a common year. The
-- is_leap_year flag exists so that can be corrected for rather than
-- silently absorbed.
--
-- Safe to re-run: the DELETE below makes this idempotent.
-- ===========================================================================

DELETE FROM dw.dim_date;

WITH days AS (
    SELECT generate_series('2021-01-01'::date,
                           '2026-12-31'::date,
                           INTERVAL '1 day')::date AS d
),
shifted AS (
    -- Shifting every date back 16 days moves the Jul 17 fiscal-year start
    -- onto Jul 1. Once the boundary lands on the 1st of a month, both
    -- fiscal columns fall out of simple month arithmetic instead of needing
    -- paired month-and-day comparisons at every quarter edge.
    SELECT d,
           d - 16 AS fd
    FROM days
)
INSERT INTO dw.dim_date (
    date_key, full_date,
    year, quarter, month, day,
    month_name, day_name,
    day_of_week, day_of_year, week_of_year,
    is_weekend, is_leap_year,
    fiscal_year, fiscal_quarter
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT,
    d,

    -- calendar parts
    EXTRACT(YEAR    FROM d)::INT,
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(MONTH   FROM d)::INT,
    EXTRACT(DAY     FROM d)::INT,

    -- TO_CHAR right-pads month and day names to 9 characters, hence TRIM
    TRIM(TO_CHAR(d, 'Month')),
    TRIM(TO_CHAR(d, 'Day')),

    -- ISODOW: Monday=1 .. Sunday=7. Plain DOW starts at Sunday=0, which
    -- sorts the week wrongly for reporting.
    EXTRACT(ISODOW FROM d)::INT,
    EXTRACT(DOY    FROM d)::INT,
    EXTRACT(WEEK   FROM d)::INT,

    EXTRACT(ISODOW FROM d) >= 6,

    -- Full Gregorian leap rule: divisible by 4, except centuries, unless
    -- divisible by 400. The century exception never fires in this range
    -- (only 2024 qualifies), but hardcoding "% 4 = 0" would quietly break
    -- the day someone widens the range past 2100.
    (   EXTRACT(YEAR FROM d)::INT % 4   = 0
    AND EXTRACT(YEAR FROM d)::INT % 100 <> 0 )
    OR  EXTRACT(YEAR FROM d)::INT % 400 = 0,

    -- Fiscal year, labelled by the calendar year it starts in: everything
    -- from 2025-07-17 to 2026-07-16 is fiscal 2025.
    CASE WHEN EXTRACT(MONTH FROM fd) >= 7
         THEN EXTRACT(YEAR FROM fd)::INT
         ELSE EXTRACT(YEAR FROM fd)::INT - 1
    END,

    -- Fiscal quarter, pure arithmetic on the shifted month: +5 rotates July
    -- to position 0, %12 wraps December round to January, /3 buckets into
    -- 0-3, +1 shifts to 1-4.
    ((EXTRACT(MONTH FROM fd)::INT + 5) % 12) / 3 + 1

FROM shifted;
