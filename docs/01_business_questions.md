# Business questions

The UST Campus Store runs two bookstore branches and two canteen branches. The store manager wants
one place to answer these questions. They decide what the mart must hold.

| # | Question | What the answer needs |
|---|---|---|
| Q1 | What are net sales per branch type, per branch and per term, with a subtotal at each level and a grand total? | `ROLLUP`; subtotals checked against the grand total |
| Q2 | How do net sales split across product category and customer type (student, staff, unknown buyer), including every subtotal of both? | `CUBE`; `GROUPING()` to label the subtotal rows |
| Q3 | What are the top 5 products of each branch in each term, by net sales? | a ranking window function |
| Q4 | For each branch: net sales per month, the change from the month before, and the running total within the term. For the canteens: a 7-day moving average of daily net sales. | `LAG`, `SUM() OVER`, a window frame |
| Q5 | Do canteen sales rise in exam weeks? Compare average daily net sales in exam weeks and other weeks. And which colleges' students spend the most per buyer? | `dim_date.is_exam_week`; a join from `dim_customer` to the shared student table |
| Q6 | After the price change of May 15, 2026: for each product whose price changed, units sold and net sales at the old price and at the new price. | the Type 2 history in `dim_product` |

Q6 can only be answered after Session 2, task 2.

## The governed metric: net sales

One definition, used everywhere:

> **Net sales** = the total of `line_amount` for SALE lines, minus the total of `line_amount` for REFUND lines.
>
> - `line_amount` is already after the discount (quantity × unit price − discount).
> - A line that the store deleted (voided) does not count.
> - A rejected row does not count.
> - Net sales is in pesos and can be added up across every dimension.

Define it once (Session 2, task 7). No query or chart may write its own version.

## Who uses the answers

| User | Sees |
|---|---|
| Store manager | all branches |
| Branch manager | only the sales of their own branch (Session 3, row-level security) |
