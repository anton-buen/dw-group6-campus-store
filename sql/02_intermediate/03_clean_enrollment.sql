-- SESSION 1, task 5: Clean the enrollment extracts             Lead: Data Architect
-- Sources: src.enroll_students, src.enroll_courses, src.enroll_enrollments.
-- If your group already wrote cleaning rules for these files in the earlier lab, reuse them.
-- Follow the class standards in docs/02_grain_and_star_schema.md:
--   student_id = trimmed, upper case;  term code = 2025-1;  5 colleges with fixed codes.

\set ON_ERROR_STOP on

BEGIN;
CREATE OR REPLACE FUNCTION int.try_parse_date(raw_val text)
RETURNS date
LANGUAGE plpgsql
AS $$
DECLARE
    v text := TRIM(raw_val);
BEGIN
    IF v IS NULL OR v = '' THEN
        RETURN NULL;
    ELSIF v ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
        RETURN v::date;
    ELSIF v ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN
        RETURN to_date(v, 'MM/DD/YYYY');
    ELSIF v ~ '^[0-9]{2}-[A-Za-z]{3}-[0-9]{4}$' THEN
        RETURN to_date(v, 'DD-Mon-YYYY');
    ELSE
        RETURN NULL;
    END IF;
EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN
    RETURN NULL;
END;
$$;

-- 1. Clean enroll_students (standardize student_id, map 5 colleges, fallback via program_code, dedupe)
DROP TABLE IF EXISTS int.int_enroll_students;
CREATE TABLE int.int_enroll_students AS
WITH normalized AS (
    SELECT
        UPPER(TRIM(student_id))                  AS student_id,
        TRIM(full_name)                          AS full_name,
        NULLIF(UPPER(TRIM(program_code)), '')    AS program_code,
        TRIM(college)                            AS raw_college,
        CASE
            WHEN LOWER(TRIM(college)) IN ('ccs', 'coll. of computer studies', 'college of computer studies') THEN 'CCS'
            WHEN LOWER(TRIM(college)) IN ('coe', 'coll. of engineering', 'college of engineering')          THEN 'CoE'
            WHEN LOWER(TRIM(college)) IN ('cba', 'college of business admin.', 'college of business administration') THEN 'CBA'
            WHEN LOWER(TRIM(college)) IN ('cal', 'coll. of arts & letters', 'college of arts & letters', 'college of arts and letters') THEN 'CAL'
            WHEN LOWER(TRIM(college)) IN ('cos', 'coll. of science', 'college of science')                  THEN 'CoS'
            -- Fallback for blank college using known program_code
            WHEN UPPER(TRIM(program_code)) IN ('BSCS', 'BSIS', 'BSIT') THEN 'CCS'
            WHEN UPPER(TRIM(program_code)) IN ('BSCE', 'BSEE', 'BSME') THEN 'CoE'
            WHEN UPPER(TRIM(program_code)) IN ('BSA', 'BSBA')          THEN 'CBA'
            WHEN UPPER(TRIM(program_code)) IN ('ABCOMM', 'ABELS')      THEN 'CAL'
            WHEN UPPER(TRIM(program_code)) IN ('BSBIO', 'BSMATH')      THEN 'CoS'
            ELSE NULL
        END                                      AS college_code,
        CASE WHEN TRIM(year_level) ~ '^[1-6]$' THEN TRIM(year_level)::smallint END AS year_level,
        ctid
    FROM stg.stg_enroll_students
),
ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY student_id
            ORDER BY
                (program_code IS NOT NULL) DESC,
                (college_code IS NOT NULL) DESC,
                (year_level IS NOT NULL) DESC,
                ctid DESC
        ) AS rn
    FROM normalized
    WHERE student_id ~ '^S[0-9]{7}$'
)
SELECT student_id, full_name, program_code, college_code, year_level
FROM ranked
WHERE rn = 1;

-- 2. Clean enroll_courses
DROP TABLE IF EXISTS int.int_enroll_courses;
CREATE TABLE int.int_enroll_courses AS
WITH ranked AS (
    SELECT
        UPPER(TRIM(course_code)) AS course_code,
        TRIM(course_title)       AS course_title,
        CASE WHEN TRIM(units) ~ '^[0-9]+$' THEN TRIM(units)::smallint END AS units,
        CASE
            WHEN LOWER(TRIM(college)) IN ('ccs', 'coll. of computer studies', 'college of computer studies') THEN 'CCS'
            WHEN LOWER(TRIM(college)) IN ('coe', 'coll. of engineering', 'college of engineering')          THEN 'CoE'
            WHEN LOWER(TRIM(college)) IN ('cba', 'college of business admin.', 'college of business administration') THEN 'CBA'
            WHEN LOWER(TRIM(college)) IN ('cal', 'coll. of arts & letters', 'college of arts & letters', 'college of arts and letters') THEN 'CAL'
            WHEN LOWER(TRIM(college)) IN ('cos', 'coll. of science', 'college of science')                  THEN 'CoS'
            ELSE NULL
        END AS college_code,
        ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(course_code)) ORDER BY ctid DESC) AS rn
    FROM stg.stg_enroll_courses
)
SELECT course_code, course_title, units, college_code
FROM ranked
WHERE rn = 1;

-- 3. Clean enroll_enrollments (standardize academic_term to 2025-1 / 2025-2)
DROP TABLE IF EXISTS int.int_enroll_enrollments;
CREATE TABLE int.int_enroll_enrollments AS
SELECT
    UPPER(TRIM(enrollment_id)) AS enrollment_id,
    UPPER(TRIM(student_id))    AS student_id,
    UPPER(TRIM(course_code))   AS course_code,
    CASE
        WHEN TRIM(academic_term) IN ('2025-1', '1st Semester 2025-2026', '2025-2026 1st Sem', 'AY2025-26 S1') THEN '2025-1'
        WHEN TRIM(academic_term) IN ('2025-2', '2nd Semester 2025-2026', '2025-2026 2nd Sem', 'AY2025-26 S2') THEN '2025-2'
        ELSE NULL
    END                        AS term_code,
    int.try_parse_date(enrollment_date) AS enrollment_date,
    UPPER(TRIM(status))        AS status
FROM stg.stg_enroll_enrollments;

COMMIT;

SELECT 'int_enroll_students'    AS table_name, COUNT(*) AS row_count FROM int.int_enroll_students
UNION ALL SELECT 'int_enroll_courses',     COUNT(*) FROM int.int_enroll_courses
UNION ALL SELECT 'int_enroll_enrollments', COUNT(*) FROM int.int_enroll_enrollments;