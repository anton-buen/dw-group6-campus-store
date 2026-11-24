-- SESSION 1, task 5: Shared tables                             Lead: Data Architect
-- From the cleaned enrollment extracts build shared.dim_college (5 rows), shared.dim_program,
-- shared.dim_student, and check shared.dim_term. The whole class will use these in the project,
-- so follow the class standards exactly.
--
-- Evidence: row counts, and a query that joins mart.dim_customer to shared.dim_student.
-- Say how many student buyers are NOT in the student table, and why that is not an error.

\set ON_ERROR_STOP on

BEGIN;

-- 1. shared.dim_college (strictly 5 standard colleges)
INSERT INTO shared.dim_college (college_code, college_name)
VALUES
    ('CCS', 'College of Computer Studies'),
    ('CoE', 'College of Engineering'),
    ('CBA', 'College of Business Administration'),
    ('CAL', 'College of Arts and Letters'),
    ('CoS', 'College of Science')
ON CONFLICT (college_code) DO UPDATE
SET college_name = EXCLUDED.college_name;

-- 2. shared.dim_program (derived from cleaned students)
INSERT INTO shared.dim_program (program_code, college_key)
SELECT DISTINCT
    s.program_code,
    c.college_key
FROM int.int_enroll_students s
JOIN shared.dim_college c
  ON s.college_code = c.college_code
WHERE s.program_code IS NOT NULL
ON CONFLICT (program_code) DO UPDATE
SET college_key = EXCLUDED.college_key;

-- 3. shared.dim_student (Type 2-ready: one current row per student)
INSERT INTO shared.dim_student (
    student_id, full_name, program_key, year_level, valid_from, valid_to, is_current
)
SELECT
    s.student_id,
    s.full_name,
    p.program_key,
    s.year_level,
    DATE '1900-01-01',
    DATE '9999-12-31',
    true
FROM int.int_enroll_students s
LEFT JOIN shared.dim_program p
  ON s.program_code = p.program_code
ON CONFLICT (student_id, valid_from) DO UPDATE
SET full_name   = EXCLUDED.full_name,
    program_key = EXCLUDED.program_key,
    year_level  = EXCLUDED.year_level;

COMMIT;

-- Evidence 1.6a: Row counts of shared dimensions
SELECT 'shared.dim_college' AS shared_table, COUNT(*) AS row_count FROM shared.dim_college
UNION ALL SELECT 'shared.dim_program', COUNT(*) FROM shared.dim_program
UNION ALL SELECT 'shared.dim_student', COUNT(*) FROM shared.dim_student
UNION ALL SELECT 'shared.dim_term',    COUNT(*) FROM shared.dim_term;

-- Evidence 1.6b: Raw college spellings found -> 5 standardized college codes
SELECT
    COALESCE(NULLIF(college, ''), '<BLANK - derived from program>') AS raw_college_spelling,
    CASE
        WHEN LOWER(TRIM(college)) IN ('ccs', 'coll. of computer studies', 'college of computer studies') THEN 'CCS'
        WHEN LOWER(TRIM(college)) IN ('coe', 'coll. of engineering', 'college of engineering')          THEN 'CoE'
        WHEN LOWER(TRIM(college)) IN ('cba', 'college of business admin.', 'college of business administration') THEN 'CBA'
        WHEN LOWER(TRIM(college)) IN ('cal', 'coll. of arts & letters', 'college of arts & letters', 'college of arts and letters') THEN 'CAL'
        WHEN LOWER(TRIM(college)) IN ('cos', 'coll. of science', 'college of science')                  THEN 'CoS'
        WHEN UPPER(TRIM(program_code)) IN ('BSME')   THEN 'CoE'
        WHEN UPPER(TRIM(program_code)) IN ('BSMATH') THEN 'CoS'
    END AS mapped_college_code,
    COUNT(*) AS raw_rows
FROM stg.stg_enroll_students
GROUP BY 1, 2
ORDER BY 2, 1;

-- Evidence 1.6c: Join mart.dim_customer to shared.dim_student + unmatched student buyers count
SELECT
    COUNT(*) FILTER (WHERE s.student_key IS NOT NULL) AS matched_student_buyers,
    COUNT(*) FILTER (WHERE s.student_key IS NULL)     AS unmatched_student_buyers,
    COUNT(*)                                          AS total_student_buyers
FROM mart.dim_customer c
LEFT JOIN shared.dim_student s
  ON c.student_id = s.student_id AND s.is_current = true
WHERE c.customer_type = 'STUDENT';

SELECT
    c.customer_id, c.student_id, s.full_name, p.program_code, col.college_code
FROM mart.dim_customer c
JOIN shared.dim_student s    ON c.student_id = s.student_id AND s.is_current = true
LEFT JOIN shared.dim_program p   ON s.program_key = p.program_key
LEFT JOIN shared.dim_college col ON p.college_key = col.college_key
ORDER BY c.customer_id
LIMIT 10;