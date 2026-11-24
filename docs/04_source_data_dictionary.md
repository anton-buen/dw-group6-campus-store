# Source data dictionary

Everything in schema `src` is text, exactly as the extract arrived. The store's rules below say what
**valid** data looks like. Not every row follows them. Finding the rows that do not is part of Session 1.

For each problem you find, decide: can a rule fix it safely (**fix**), or not (**reject**)?
A row that cannot be fixed by a rule goes to your reject table with a reason. Do not guess a value.

## src.sales — one row per receipt line

| Column | Meaning | Store's rule |
|---|---|---|
| `receipt_no` | receipt number: branch, date, running number | with `line_no`, identifies one receipt line |
| `line_no` | line on the receipt, from 1 | |
| `sold_at` | when the sale happened, Manila time | a real date and time. The POS has exported this in more than one format over the years; all formats mean the same thing |
| `branch_code` | where | must be a branch in `src.branches`. Letter case and spaces around a code do not matter |
| `product_code` | what | must be a product in `src.products`. Letter case and spaces around a code do not matter |
| `customer_id` | who, if the buyer showed an ID | optional. Empty = walk-in. An id that is not in `src.customers` is still a real sale to an unknown buyer |
| `txn_type` | `SALE` or `REFUND` | only these two words, in any letter case |
| `quantity` | units | a whole number greater than 0, also on a refund |
| `unit_price` | pesos per unit on the day of the sale | a number; some exports add a currency label or a thousands comma |
| `discount` | pesos taken off the line | a number; empty means 0 |
| `line_total` | pesos charged for the line | must equal quantity × unit_price − discount |
| `payment_method` | `CASH`, `GCASH` or `CARD` | |
| `updated_at` | last time the POS wrote this row | always `YYYY-MM-DD HH:MM:SS`. Safe to use as a watermark |
| `order_channel` | how the order was placed | appears only after the POS upgrade (file 05) |

More rules for sales:

- The POS sometimes sends the same line more than once. If the copies are exactly equal, keep one.
  If they differ, the copy with the newest `updated_at` is the correct one.
- A refund is its own receipt line with `txn_type = REFUND`, positive `quantity` and positive `line_total`. It lowers net sales.
- Every branch sells Monday to Saturday in term time. A branch whose newest sale is more than 2 days
  older than the load date is **stale**: something is wrong with its feed.
- Load dates to use: Session 1 = **2026-05-01**. After that, the day after the newest sale in the file you just loaded.

## src.sales_change_log — one row per change event (file 03)

| Column | Meaning |
|---|---|
| `lsn` | log sequence number. A higher number happened later. This is the order to apply events in |
| `xid` | transaction id. Lines of one receipt share it |
| `op` | `I` insert, `U` update, `D` delete |
| `committed_at` | when the change was saved in the POS. Use it as the row's `updated_at` |
| the sales columns | for `I` and `U`: the full row after the change. For `D`: only `receipt_no` and `line_no` |

The vendor promises each event **at least once**. It does not promise exactly once.

## src.sales_reextract_20260317 — one past day sent again (file 06)

Same columns as `src.sales` before the upgrade. Holds every sale of 2026-03-17 for all branches.

## src.products — one row per product

| Column | Meaning | Store's rule |
|---|---|---|
| `product_code` | `BK-` bookstore, `CN-` canteen, then 4 digits | one row per product |
| `product_name` | | |
| `category` | | may be empty; then use `Uncategorized` |
| `unit_price` | the **current** price in pesos | the source overwrites this when a price changes. It keeps no history |
| `is_active` | `Y` or `N` | |
| `updated_at` | last change to the row | a price change takes effect at this time |

## src.branches — one row per branch

`branch_code`, `branch_name`, `branch_type` (`BOOKSTORE` or `CANTEEN`), `building`, `opened_on`.

## src.customers — one row per registered buyer

| Column | Meaning | Store's rule |
|---|---|---|
| `customer_id` | store's own id, `C` + 4 digits | one row per buyer |
| `customer_type` | `STUDENT` or `STAFF` | in any letter case |
| `id_number` | student id (`S` + 7 digits) or staff number (`EMP-…`) | follows the class standard for student ids after cleaning |
| `full_name` | | |
| `registered_on` | | |

A student buyer who is not in the enrollment extract is still a valid buyer (for example an older student).

## src.academic_calendar — one row per term

`term_code`, `academic_year`, `term_name`, `start_date`, `end_date`, and the first and last day of the
prelim and final exam weeks. This table is clean.

## The enrollment extracts

`src.enroll_students` (`student_id`, `full_name`, `program_code`, `college`, `year_level`),
`src.enroll_courses` (`course_code`, `course_title`, `units`, `college`),
`src.enroll_enrollments` (`enrollment_id`, `student_id`, `course_code`, `academic_term`, `enrollment_date`, `status`).

These are the registrar's raw extracts, with the same kinds of problems you met earlier in the course.
Clean them to the class standards in `02_grain_and_star_schema.md`, then build the shared tables.
There are 5 real colleges, however many ways the name is typed.
