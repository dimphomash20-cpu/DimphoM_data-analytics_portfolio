/* ============================================================
   INSURANCE CHARGES: SQL ANALYSIS (MySQL 8.0+)

   QUESTION
     Which customer characteristics drive higher insurance charges,
     and how can they be used to set prices and group customers by risk?

   DATA
     insurance.csv, cleaned in Excel first (1 duplicate row removed,
     leaving 1,337 customers). Columns: age, sex, bmi, children,
     smoker, region, charges.

   KEY FINDINGS
     - Smokers are 20.5% of customers but 49.5% of all charges
       ($32,050 average vs $8,441 for non-smokers, 3.8 times more).
     - BMI matters mostly for smokers: obese smokers average $41,558,
       about double smokers with a normal BMI ($19,942).
     - Charges rise with age, from $9,201 (18-29) to $17,903 (50-64).
     - The top 10% of customers account for 32% of all charges.
     - Obese smokers are 10.8% of customers but 33.9% of charges.
     - Region and sex matter little compared with smoking.
     These are associations, not proof of cause.
   ============================================================ */

CREATE DATABASE IF NOT EXISTS insurance_db;
USE insurance_db;

CREATE TABLE IF NOT EXISTS insurance (
    id        INT AUTO_INCREMENT PRIMARY KEY,
    age       INT            NOT NULL,
    sex       VARCHAR(10)    NOT NULL,
    bmi       DECIMAL(6,3)   NOT NULL,
    children  INT            NOT NULL,
    smoker    VARCHAR(3)     NOT NULL,
    region    VARCHAR(20)    NOT NULL,
    charges   DECIMAL(12,5)  NOT NULL
);

-- Adds two groupings used by the queries below:
--   age_band     (18-29, 30-39, 40-49, 50-64)
--   bmi_category (Underweight, Normal, Overweight, Obese; 30+ = Obese)
CREATE OR REPLACE VIEW insurance_analysis AS
SELECT
    id, age, sex, bmi, children, smoker, region, charges,
    CASE WHEN age < 30 THEN '18-29'
         WHEN age < 40 THEN '30-39'
         WHEN age < 50 THEN '40-49'
         ELSE '50-64' END AS age_band,
    CASE WHEN bmi < 18.5 THEN 'Underweight'
         WHEN bmi < 25   THEN 'Normal'
         WHEN bmi < 30   THEN 'Overweight'
         ELSE 'Obese' END AS bmi_category
FROM insurance;


-- THE BIG PICTURE: average, median, lowest and highest charge.
--     The median ($9,386) is well below the average ($13,279), because
--     a few very expensive customers pull the average up.
WITH ordered AS (
    SELECT charges,
           ROW_NUMBER() OVER (ORDER BY charges) AS rn,
           COUNT(*) OVER ()                     AS n
    FROM insurance_analysis
)
SELECT
    (SELECT COUNT(*) FROM insurance_analysis)               AS customers,
    ROUND((SELECT AVG(charges) FROM insurance_analysis), 2) AS avg_charge,
    ROUND((SELECT AVG(charges) FROM ordered
           WHERE rn IN (FLOOR((n + 1) / 2), FLOOR((n + 2) / 2))), 2) AS median_charge,
    ROUND((SELECT MIN(charges) FROM insurance_analysis), 2) AS min_charge,
    ROUND((SELECT MAX(charges) FROM insurance_analysis), 2) AS max_charge
LIMIT 1;

-- SMOKERS VS NON-SMOKERS: how many, average charge, and share of all
--     charges. Smokers are 20.5% of customers but 49.5% of charges.
SELECT smoker,
       COUNT(*)                                                    AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_customers,
       ROUND(AVG(charges), 2)                                      AS avg_charge,
       ROUND(100.0 * SUM(charges) / SUM(SUM(charges)) OVER (), 1)  AS pct_of_total_charges
FROM insurance_analysis
GROUP BY smoker
ORDER BY avg_charge DESC;

-- HOW MANY TIMES MORE DO SMOKERS COST? (Answer: 3.8 times.)
SELECT ROUND(
    (SELECT AVG(charges) FROM insurance_analysis WHERE smoker = 'yes') /
    (SELECT AVG(charges) FROM insurance_analysis WHERE smoker = 'no'), 2) AS smoker_premium_multiple;

-- BY REGION: southeast is highest, southwest lowest, but the gap is small.
SELECT region, COUNT(*) AS customers, ROUND(AVG(charges), 2) AS avg_charge
FROM insurance_analysis
GROUP BY region
ORDER BY avg_charge DESC;

-- BY SEX: males average slightly more than females.
SELECT sex, COUNT(*) AS customers, ROUND(AVG(charges), 2) AS avg_charge
FROM insurance_analysis
GROUP BY sex
ORDER BY avg_charge DESC;

-- BY NUMBER OF CHILDREN: no clear pattern.
SELECT children, COUNT(*) AS customers, ROUND(AVG(charges), 2) AS avg_charge
FROM insurance_analysis
GROUP BY children
ORDER BY children;

-- BY AGE: charges climb steadily as people get older.
SELECT age_band, COUNT(*) AS customers, ROUND(AVG(charges), 2) AS avg_charge
FROM insurance_analysis
GROUP BY age_band
ORDER BY age_band;

-- BY BMI CATEGORY: the obese group is the most expensive.
SELECT bmi_category, COUNT(*) AS customers, ROUND(AVG(charges), 2) AS avg_charge
FROM insurance_analysis
GROUP BY bmi_category
ORDER BY avg_charge DESC;

-- SMOKING AND BMI TOGETHER: does BMI matter more for smokers?
--     Yes. Obese smokers average $41,558. Obese non-smokers average $8,856.
SELECT smoker, bmi_category, COUNT(*) AS customers, ROUND(AVG(charges), 2) AS avg_charge
FROM insurance_analysis
GROUP BY smoker, bmi_category
ORDER BY smoker, avg_charge DESC;

-- SMOKING AND AGE TOGETHER: smokers cost far more at every age.
SELECT age_band, smoker, COUNT(*) AS customers, ROUND(AVG(charges), 2) AS avg_charge
FROM insurance_analysis
GROUP BY age_band, smoker
ORDER BY age_band, smoker;

-- SMOKERS BY REGION: what percent of each region smokes?
--      Southeast has the most smokers (25%) and also the highest average
--      charge, which may be connected.
SELECT region,
       COUNT(*) AS customers,
       ROUND(100.0 * SUM(CASE WHEN smoker = 'yes' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_smokers
FROM insurance_analysis
GROUP BY region
ORDER BY pct_smokers DESC;

-- WHICH FACTOR EXPLAINS CHARGES BEST? Scores run from 0 (no link) to
--      1 (perfect link). Smoking scores 0.62, far above age (0.09),
--      BMI (0.04) and children (0.005). Smoking is the main driver.
SELECT 'age' AS variable,
       ROUND(cov_xy * cov_xy / (var_x * var_y), 3) AS r_squared
FROM (
    SELECT AVG(age * charges) - AVG(age) * AVG(charges)         AS cov_xy,
           AVG(age * age)     - AVG(age) * AVG(age)             AS var_x,
           AVG(charges * charges) - AVG(charges) * AVG(charges) AS var_y
    FROM insurance_analysis
) AS a
UNION ALL
SELECT 'bmi',
       ROUND(cov_xy * cov_xy / (var_x * var_y), 3)
FROM (
    SELECT AVG(bmi * charges) - AVG(bmi) * AVG(charges)         AS cov_xy,
           AVG(bmi * bmi)     - AVG(bmi) * AVG(bmi)             AS var_x,
           AVG(charges * charges) - AVG(charges) * AVG(charges) AS var_y
    FROM insurance_analysis
) AS b
UNION ALL
SELECT 'children',
       ROUND(cov_xy * cov_xy / (var_x * var_y), 3)
FROM (
    SELECT AVG(children * charges) - AVG(children) * AVG(charges)   AS cov_xy,
           AVG(children * children) - AVG(children) * AVG(children) AS var_x,
           AVG(charges * charges) - AVG(charges) * AVG(charges)     AS var_y
    FROM insurance_analysis
) AS c
UNION ALL
SELECT 'smoker (1=yes)',
       ROUND(cov_xy * cov_xy / (var_x * var_y), 3)
FROM (
    SELECT AVG(CASE WHEN smoker = 'yes' THEN charges ELSE 0 END)
             - AVG(CASE WHEN smoker = 'yes' THEN 1 ELSE 0 END) * AVG(charges) AS cov_xy,
           AVG(CASE WHEN smoker = 'yes' THEN 1 ELSE 0 END)
             - AVG(CASE WHEN smoker = 'yes' THEN 1 ELSE 0 END)
             * AVG(CASE WHEN smoker = 'yes' THEN 1 ELSE 0 END)                AS var_x,
           AVG(charges * charges) - AVG(charges) * AVG(charges)               AS var_y
    FROM insurance_analysis
) AS d;


-- COST TIERS: customers split into three equal groups by charge.
--     The High tier is 61% smokers; the Low tier has almost none.
WITH tiers AS (
    SELECT *, NTILE(3) OVER (ORDER BY charges) AS tier_no
    FROM insurance_analysis
)
SELECT CASE tier_no WHEN 1 THEN 'Low' WHEN 2 THEN 'Medium' ELSE 'High' END AS charge_tier,
       COUNT(*)                                   AS customers,
       ROUND(MIN(charges), 2)                     AS min_charge,
       ROUND(MAX(charges), 2)                     AS max_charge,
       ROUND(AVG(charges), 2)                     AS avg_charge,
       ROUND(100.0 * SUM(CASE WHEN smoker = 'yes' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_smokers,
       ROUND(AVG(bmi), 1)                         AS avg_bmi,
       ROUND(AVG(age), 1)                         AS avg_age
FROM tiers
GROUP BY tier_no
ORDER BY tier_no;

-- WHO PAYS THE MOST? Customers split into ten equal groups.
--     Decile 1 = the most expensive 10% of customers. They account for
--     32% of all charges. The cumulative column adds the groups up.
WITH ranked AS (
    SELECT charges, NTILE(10) OVER (ORDER BY charges DESC) AS decile
    FROM insurance_analysis
)
SELECT decile,
       COUNT(*)                                                    AS customers,
       ROUND(SUM(charges), 0)                                      AS total_charges,
       ROUND(100.0 * SUM(charges) / SUM(SUM(charges)) OVER (), 1)  AS pct_of_total,
       ROUND(100.0 * SUM(SUM(charges)) OVER (ORDER BY decile)
             / SUM(SUM(charges)) OVER (), 1)                       AS cumulative_pct
FROM ranked
GROUP BY decile
ORDER BY decile;

-- RISK SEGMENTS: five groups an insurer could price differently.
--     'Smoker + obese' is 10.8% of customers but 33.9% of all charges.
SELECT CASE
           WHEN smoker = 'yes' AND bmi >= 30 THEN '1. Smoker + obese'
           WHEN smoker = 'yes'               THEN '2. Smoker, BMI under 30'
           WHEN bmi >= 30 AND age >= 50      THEN '3. Non-smoker, obese, 50+'
           WHEN age >= 50                    THEN '4. Non-smoker, 50+'
           ELSE                                   '5. Non-smoker, under 50'
       END AS risk_segment,
       COUNT(*)                                                    AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_customers,
       ROUND(AVG(charges), 2)                                      AS avg_charge,
       ROUND(100.0 * SUM(charges) / SUM(SUM(charges)) OVER (), 1)  AS pct_of_total_charges
FROM insurance_analysis
GROUP BY risk_segment
ORDER BY risk_segment;

-- SMOKER PREMIUM AT EACH AGE: how many times more smokers cost than
--     non-smokers in the same age band (6.2x for young, 2.9x for 50+).
SELECT age_band,
       ROUND(AVG(CASE WHEN smoker = 'yes' THEN charges END), 2) AS avg_smoker,
       ROUND(AVG(CASE WHEN smoker = 'no'  THEN charges END), 2) AS avg_non_smoker,
       ROUND(AVG(CASE WHEN smoker = 'yes' THEN charges END) /
             AVG(CASE WHEN smoker = 'no'  THEN charges END), 2) AS premium_multiple
FROM insurance_analysis
GROUP BY age_band
ORDER BY age_band;

-- WHO ARE THE MOST EXPENSIVE 25%? Compared with everyone else.
--     76% of them are smokers, versus about 2% of the rest.
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY charges) AS rn, COUNT(*) OVER () AS n
    FROM insurance_analysis
),
cut AS (
    SELECT charges AS threshold
    FROM ranked
    WHERE rn = FLOOR(0.75 * n)
)
SELECT CASE WHEN r.charges > cut.threshold THEN 'High cost (top 25%)' ELSE 'Other' END AS grp,
       COUNT(*)                                                                        AS customers,
       ROUND(100.0 * SUM(CASE WHEN r.smoker = 'yes' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_smokers,
       ROUND(100.0 * SUM(CASE WHEN r.bmi >= 30 THEN 1 ELSE 0 END) / COUNT(*), 1)      AS pct_obese,
       ROUND(AVG(r.age), 1)                                                            AS avg_age,
       ROUND(AVG(r.charges), 2)                                                        AS avg_charge
FROM ranked r CROSS JOIN cut
GROUP BY grp
ORDER BY grp;


-- TOP 3 MOST EXPENSIVE CUSTOMERS IN EACH REGION (all are smokers).
SELECT region, rank_in_region, age, sex, bmi, smoker, ROUND(charges, 2) AS charges
FROM (
    SELECT region, age, sex, bmi, smoker, charges,
           RANK() OVER (PARTITION BY region ORDER BY charges DESC) AS rank_in_region
    FROM insurance_analysis
) AS t
WHERE rank_in_region <= 3
ORDER BY region, rank_in_region;

-- WHO IS FURTHEST ABOVE THEIR REGION'S AVERAGE? Top 10 customers.
SELECT id, region, smoker, ROUND(charges, 2) AS charges,
       ROUND(AVG(charges) OVER (PARTITION BY region), 2)           AS region_avg,
       ROUND(charges - AVG(charges) OVER (PARTITION BY region), 2) AS diff_from_region_avg
FROM insurance_analysis
ORDER BY diff_from_region_avg DESC
LIMIT 10;

-- THE COSTLIEST NON-SMOKERS: percentile rank of 1.0 means the most
--     expensive person in the non-smoker group.
SELECT * FROM (
    SELECT id, smoker, age, ROUND(charges, 2) AS charges,
           ROUND(PERCENT_RANK() OVER (PARTITION BY smoker ORDER BY charges), 3) AS pct_rank_in_group
    FROM insurance_analysis
) AS t
WHERE smoker = 'no'
ORDER BY pct_rank_in_group DESC
LIMIT 10;

-- HELPER STEP (no output): finds the charge that 25% of customers fall
--     below (Q1) and 75% fall below (Q3). Used by the outlier checks next.
CREATE OR REPLACE VIEW charge_quartiles AS
WITH ordered AS (
    SELECT charges,
           ROW_NUMBER() OVER (ORDER BY charges) AS rn,
           COUNT(*) OVER ()                     AS n
    FROM insurance_analysis
),
pos AS (
    SELECT DISTINCT 1 + 0.25 * (n - 1) AS p1,
                    1 + 0.75 * (n - 1) AS p3
    FROM ordered
)
SELECT
    (SELECT charges FROM ordered WHERE rn = FLOOR(p1))
      + (p1 - FLOOR(p1))
      * ((SELECT charges FROM ordered WHERE rn = FLOOR(p1) + 1)
         - (SELECT charges FROM ordered WHERE rn = FLOOR(p1))) AS q1,
    (SELECT charges FROM ordered WHERE rn = FLOOR(p3))
      + (p3 - FLOOR(p3))
      * ((SELECT charges FROM ordered WHERE rn = FLOOR(p3) + 1)
         - (SELECT charges FROM ordered WHERE rn = FLOOR(p3))) AS q3
FROM pos;

-- HOW MANY UNUSUALLY EXPENSIVE CUSTOMERS? Anyone above the 'upper
--     fence' counts as an outlier: 139 customers, 10.4% of the total.
SELECT ROUND(q.q1, 2)                       AS q1,
       ROUND(q.q3, 2)                       AS q3,
       ROUND(q.q3 + 1.5 * (q.q3 - q.q1), 2) AS upper_fence,
       (SELECT COUNT(*) FROM insurance_analysis c
        WHERE c.charges > q.q3 + 1.5 * (q.q3 - q.q1)) AS outliers,
       ROUND(100.0 * (SELECT COUNT(*) FROM insurance_analysis c
                      WHERE c.charges > q.q3 + 1.5 * (q.q3 - q.q1))
             / (SELECT COUNT(*) FROM insurance_analysis), 1) AS pct_outliers
FROM charge_quartiles q;

-- WHO ARE THEY? 136 of the 139 are smokers.
SELECT c.smoker,
       COUNT(*)                 AS outliers,
       ROUND(AVG(c.charges), 2) AS avg_charge,
       ROUND(AVG(c.bmi), 1)     AS avg_bmi
FROM insurance_analysis c
CROSS JOIN charge_quartiles q
WHERE c.charges > q.q3 + 1.5 * (q.q3 - q.q1)
GROUP BY c.smoker;

-- SMOOTHED TREND BY AGE: average charge at ages 20, 30, 40, 50 and 60,
--     smoothed over neighbouring ages so the trend is easier to read.
WITH by_age AS (
    SELECT age, smoker, AVG(charges) AS avg_charge
    FROM insurance_analysis
    GROUP BY age, smoker
),
smoothed AS (
    SELECT age, smoker, avg_charge,
           AVG(avg_charge) OVER (
               PARTITION BY smoker ORDER BY age
               ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS moving_avg
    FROM by_age
)
SELECT age, smoker,
       ROUND(avg_charge, 0) AS avg_charge,
       ROUND(moving_avg, 0) AS moving_avg_5_ages
FROM smoothed
WHERE age IN (20, 30, 40, 50, 60)
ORDER BY smoker, age;

-- REGIONS RANKED BY TOTAL CHARGES, with each region's share.
SELECT region,
       ROUND(SUM(charges), 0)                                      AS total_charges,
       ROUND(100.0 * SUM(charges) / SUM(SUM(charges)) OVER (), 1)  AS pct_of_total,
       RANK() OVER (ORDER BY SUM(charges) DESC)                    AS rank_by_total
FROM insurance_analysis
GROUP BY region
ORDER BY rank_by_total;
