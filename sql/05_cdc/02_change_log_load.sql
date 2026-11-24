-- SESSION 2, task 1b: CDC with a change log                    Lead: ETL Engineer
-- Run source/03_change_log_may08_to_14.sql. It creates src.sales_change_log.
-- These changes are NOT in src.sales. Apply the log to your warehouse:
--   I = insert,  U = update (the row holds the full new values),  D = delete (key only)
-- Think about: the order of events (lsn), a row changed more than once, an event that is
-- delivered twice, and what a delete should do to your fact table and to later reruns.
-- Save the last lsn you applied.
--
-- Evidence: events read, events applied by type, last lsn, one deleted row shown gone,
-- and proof that applying the same log a second time changes nothing.
\set ON_ERROR_STOP on

BEGIN;

-- 1. Persistent tombstone table so deletes are respected on later reruns (Task 5)
CREATE TABLE IF NOT EXISTS audit.deleted_sales_keys (
    receipt_no      text NOT NULL,
    line_no         integer NOT NULL,
    deleted_lsn     bigint NOT NULL,
    deleted_at      timestamp,
    recorded_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (receipt_no, line_no)
);

-- 2. Ensure watermark row exists for the change log stream
INSERT INTO audit.watermarks (stream_name, last_watermark, last_lsn)
VALUES ('sales_change_log', TIMESTAMP '1900-01-01', 0)
ON CONFLICT (stream_name) DO NOTHING;

-- Temp table to report this run's stats cleanly after COMMIT
CREATE TEMP TABLE tmp_cdc_run_stats (
    lsn_before       bigint,
    lsn_after        bigint,
    events_read      integer,
    dupes_skipped    integer,
    applied_insert   integer,
    applied_update   integer,
    applied_delete   integer,
    rows_rejected    integer
);

DO $$
DECLARE
    v_lsn_before     bigint;
    v_lsn_after      bigint;
    v_events_read    integer := 0;
    v_dupes_skipped  integer := 0;
    v_applied_i      integer := 0;
    v_applied_u      integer := 0;
    v_applied_d      integer := 0;
    v_rejected       integer := 0;
    rec              RECORD;

    v_receipt_no     text;
    v_line_no        integer;
    v_sold_at        timestamp;
    v_branch_code    text;
    v_product_code   text;
    v_customer_id    text;
    v_txn_type       text;
    v_qty            integer;
    v_unit_price     numeric(10,2);
    v_discount       numeric(10,2);
    v_line_amount    numeric(12,2);
    v_pay_method     text;
    v_committed_at   timestamp;

    v_date_key       integer;
    v_term_key       integer;
    v_branch_key     integer;
    v_product_key    integer;
    v_customer_key   integer;
    v_reject_reason  text;
BEGIN
    SELECT COALESCE(last_lsn, 0) INTO v_lsn_before
    FROM audit.watermarks
    WHERE stream_name = 'sales_change_log';

    v_lsn_after := v_lsn_before;

    -- Count total raw events newer than last_lsn (including any duplicate deliveries)
    SELECT COUNT(*) INTO v_events_read
    FROM src.sales_change_log
    WHERE lsn::bigint > v_lsn_before;

    SELECT COUNT(*) - COUNT(DISTINCT lsn::bigint) INTO v_dupes_skipped
    FROM src.sales_change_log
    WHERE lsn::bigint > v_lsn_before;

    -- Replay deduplicated events strictly in LSN order
    FOR rec IN
        SELECT DISTINCT ON (lsn::bigint)
            lsn::bigint AS lsn_num,
            UPPER(TRIM(op)) AS op_code,
            committed_at, receipt_no, line_no, sold_at, branch_code, product_code,
            customer_id, txn_type, quantity, unit_price, discount, line_total, payment_method
        FROM src.sales_change_log
        WHERE lsn::bigint > v_lsn_before
        ORDER BY lsn::bigint ASC
    LOOP
        v_receipt_no   := TRIM(rec.receipt_no);
        v_line_no      := CASE WHEN TRIM(rec.line_no) ~ '^[1-9][0-9]*$' THEN TRIM(rec.line_no)::integer END;
        v_committed_at := int.try_parse_timestamp(rec.committed_at);

        IF rec.op_code = 'D' THEN
            DELETE FROM mart.fct_sales
            WHERE receipt_no = v_receipt_no
              AND line_no    = v_line_no;

            INSERT INTO audit.deleted_sales_keys (receipt_no, line_no, deleted_lsn, deleted_at)
            VALUES (v_receipt_no, v_line_no, rec.lsn_num, v_committed_at)
            ON CONFLICT (receipt_no, line_no) DO UPDATE
            SET deleted_lsn = EXCLUDED.deleted_lsn,
                deleted_at  = EXCLUDED.deleted_at,
                recorded_at = now();

            v_applied_d := v_applied_d + 1;

        ELSIF rec.op_code IN ('I', 'U') THEN
            v_sold_at      := int.try_parse_timestamp(rec.sold_at);
            v_branch_code  := UPPER(TRIM(rec.branch_code));
            v_product_code := UPPER(TRIM(rec.product_code));
            v_customer_id  := NULLIF(UPPER(TRIM(rec.customer_id)), '');
            v_txn_type     := UPPER(TRIM(rec.txn_type));
            v_qty          := CASE WHEN TRIM(rec.quantity) ~ '^[1-9][0-9]*$' THEN TRIM(rec.quantity)::integer END;
            v_unit_price   := CASE WHEN REPLACE(REPLACE(REPLACE(TRIM(rec.unit_price), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
                                   THEN REPLACE(REPLACE(REPLACE(TRIM(rec.unit_price), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) END;
            v_discount     := CASE WHEN NULLIF(TRIM(rec.discount), '') IS NULL THEN 0.00
                                   WHEN REPLACE(REPLACE(REPLACE(TRIM(rec.discount), 'PHP', ''), ',', ''), ' ', '') ~ '^[0-9]+(\.[0-9]+)?$'
                                   THEN REPLACE(REPLACE(REPLACE(TRIM(rec.discount), 'PHP', ''), ',', ''), ' ', '')::numeric(10,2) END;
            v_line_amount  := CASE WHEN REPLACE(REPLACE(REPLACE(TRIM(rec.line_total), 'PHP', ''), ',', ''), ' ', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
                                   THEN REPLACE(REPLACE(REPLACE(TRIM(rec.line_total), 'PHP', ''), ',', ''), ' ', '')::numeric(12,2) END;
            v_pay_method   := UPPER(TRIM(rec.payment_method));

            -- Lookup surrogate keys
            SELECT date_key, term_key INTO v_date_key, v_term_key
            FROM shared.dim_date WHERE full_date = v_sold_at::date;

            SELECT branch_key INTO v_branch_key
            FROM mart.dim_branch WHERE branch_code = v_branch_code;

            SELECT product_key INTO v_product_key
            FROM mart.dim_product
            WHERE product_code = v_product_code
              AND v_sold_at >= valid_from AND v_sold_at < valid_to;

            SELECT COALESCE((SELECT customer_key FROM mart.dim_customer WHERE customer_id = v_customer_id), -1)
            INTO v_customer_key;

            -- Validate
            v_reject_reason := CASE
                WHEN v_sold_at IS NULL OR v_date_key IS NULL THEN 'INVALID_SOLD_AT_DATE'
                WHEN v_qty IS NULL OR v_qty <= 0             THEN 'INVALID_QUANTITY'
                WHEN v_txn_type NOT IN ('SALE', 'REFUND')    THEN 'INVALID_TXN_TYPE'
                WHEN v_branch_key IS NULL                    THEN 'UNKNOWN_BRANCH'
                WHEN v_product_key IS NULL                   THEN 'UNKNOWN_PRODUCT'
                WHEN v_unit_price IS NULL OR v_line_amount IS NULL
                  OR ROUND(v_qty * v_unit_price - v_discount, 2) <> ROUND(v_line_amount, 2)
                                                             THEN 'LINE_TOTAL_MATH_MISMATCH'
                ELSE NULL
            END;

            IF v_reject_reason IS NOT NULL THEN
                INSERT INTO rej.rej_sales (
                    receipt_no, line_no, sold_at, branch_code, product_code, customer_id,
                    txn_type, quantity, unit_price, discount, line_total, payment_method,
                    updated_at, batch_id, reject_reason
                ) VALUES (
                    rec.receipt_no, rec.line_no, rec.sold_at, rec.branch_code, rec.product_code, rec.customer_id,
                    rec.txn_type, rec.quantity, rec.unit_price, rec.discount, rec.line_total, rec.payment_method,
                    rec.committed_at, 'S2_CHANGELOG_MAY14', v_reject_reason
                );
                v_rejected := v_rejected + 1;
            ELSE
                INSERT INTO mart.fct_sales (
                    receipt_no, line_no, date_key, term_key, branch_key, product_key, customer_key,
                    txn_type, payment_method, quantity, unit_price, discount_amount, line_amount,
                    sold_at, source_updated_at
                ) VALUES (
                    v_receipt_no, v_line_no, v_date_key, v_term_key, v_branch_key, v_product_key, v_customer_key,
                    v_txn_type, v_pay_method, v_qty, v_unit_price, v_discount, v_line_amount,
                    v_sold_at, v_committed_at
                )
                ON CONFLICT (receipt_no, line_no) DO UPDATE
                SET date_key          = EXCLUDED.date_key,
                    term_key          = EXCLUDED.term_key,
                    branch_key        = EXCLUDED.branch_key,
                    product_key       = EXCLUDED.product_key,
                    customer_key      = EXCLUDED.customer_key,
                    txn_type          = EXCLUDED.txn_type,
                    payment_method    = EXCLUDED.payment_method,
                    quantity          = EXCLUDED.quantity,
                    unit_price        = EXCLUDED.unit_price,
                    discount_amount   = EXCLUDED.discount_amount,
                    line_amount       = EXCLUDED.line_amount,
                    sold_at           = EXCLUDED.sold_at,
                    source_updated_at = EXCLUDED.source_updated_at,
                    loaded_at         = now();

                -- If a previously deleted key is re-inserted later, remove its tombstone
                DELETE FROM audit.deleted_sales_keys
                WHERE receipt_no = v_receipt_no AND line_no = v_line_no;

                IF rec.op_code = 'I' THEN
                    v_applied_i := v_applied_i + 1;
                ELSE
                    v_applied_u := v_applied_u + 1;
                END IF;
            END IF;
        END IF;

        IF rec.lsn_num > v_lsn_after THEN
            v_lsn_after := rec.lsn_num;
        END IF;
    END LOOP;

    -- Save new last_lsn
    UPDATE audit.watermarks
    SET last_lsn   = v_lsn_after,
        updated_at = now()
    WHERE stream_name = 'sales_change_log';

    INSERT INTO tmp_cdc_run_stats VALUES (
        v_lsn_before, v_lsn_after, v_events_read, v_dupes_skipped,
        v_applied_i, v_applied_u, v_applied_d, v_rejected
    );
END;
$$;

COMMIT;

-- Evidence 2.2a: Events read, applied by type (I, U, D), dupes skipped, and last_lsn saved
SELECT * FROM tmp_cdc_run_stats;

-- Evidence 2.2b: Deleted rows shown gone from mart.fct_sales
SELECT
    d.receipt_no,
    d.line_no,
    d.deleted_lsn,
    CASE WHEN f.sales_key IS NULL THEN 'GONE (deleted from fct_sales)' ELSE 'STILL PRESENT' END AS warehouse_status
FROM audit.deleted_sales_keys d
LEFT JOIN mart.fct_sales f
  ON d.receipt_no = f.receipt_no
 AND d.line_no    = f.line_no
ORDER BY d.deleted_lsn;

-- Current fct_sales totals (compare Run 1 vs Run 2 to prove idempotency)
SELECT COUNT(*) AS fct_sales_rows, SUM(line_amount) AS fct_sales_pesos
FROM mart.fct_sales;
