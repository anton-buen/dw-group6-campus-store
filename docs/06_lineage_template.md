# Lineage: from source files to the dashboard

Replace this diagram with your own. Name the real tables, views and scripts in your repository.
Show at least one column traced from start to end, for example `line_total` → `line_amount` → net sales.

```mermaid
flowchart LR
    A[source files] --> B[src tables]
    B --> C[stg_ staging]
    C --> D[int_ cleaned]
    D --> E[rej_ rejected rows]
    D --> F[dim_ and fct_ tables]
    F --> G[net sales metric]
    G --> H[dashboard]
```

For each arrow, write which script moves the data and what it changes.
