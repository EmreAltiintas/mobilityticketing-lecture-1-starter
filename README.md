# MobilityTicketing

Databases for Developers (E2026), weekly implementation labs on a fictional
city mobility and ticketing platform (buses, trams, trains), building toward
Compulsory Assignment #1 (due 2026-10-05).

The domain: customers search routes, buy digital tickets, and validate them
when boarding; operators maintain routes/timetables and view usage/revenue
reports. See `docs/week35-dossier.md` for the full design-brief write-up.

## Setup

Requirements: Docker Desktop with Compose.

```bash
docker compose up -d
```

This starts PostgreSQL 17 (`localhost:5432`, db `mobility`, user/password
`mobility`) and runs every script under `database/postgres/init/` in
filename order (route/stop baseline, seed data, the week-36 ticketing
tables and their seed, the week-38 migration fixture). Migrations are
**not** run automatically, apply them explicitly, in this order:

```bash
docker compose exec -T postgres psql -U mobility -d mobility \
  < database/postgres/migrations/011_ticketing_integrity.sql
docker compose exec -T postgres psql -U mobility -d mobility \
  < database/postgres/migrations/020_reporting_function.sql
docker compose exec -T postgres psql -U mobility -d mobility \
  < database/postgres/migrations/021_daily_revenue_trigger.sql
docker compose exec -T postgres psql -U mobility -d mobility \
  < database/postgres/migrations/022_daily_captured_revenue.sql
docker compose exec -T postgres psql -U mobility -d mobility \
  < database/postgres/migrations/030_expand_product_identity.sql
docker compose exec -T postgres psql -U mobility -d mobility \
  < database/postgres/migrations/031_backfill_ticket_product.sql
docker compose exec -T postgres psql -U mobility -d mobility \
  < database/postgres/migrations/032_require_ticket_product.sql
```

This leaves the schema at the same point the week-38 evidence starts from:
`tickets.product_id` is required, and the legacy `tickets.product_code`
column is still present alongside it (its removal was only rehearsed on a
disposable branch, see `docs/evidence/lecture04/README.md`, step 9, and
was never folded into a migration file here).

To wipe and replay everything from scratch:

```bash
docker compose down -v
docker compose up -d
```

## Repository layout

```
database/postgres/
  init/         baseline schema + seed data, run automatically on container start
  migrations/   constraint / schema-change migrations, applied by hand and recorded here
  experiments/  negative-test SQL: statements that must be rejected once a migration is applied
  queries/      the released workload queries for each week
docs/
  weekNN-*.md   per-week write-ups: dossier notes, integrity maps, ER diagrams, evidence
```

## Weekly log

| Week | Topic | Key files |
| --- | --- | --- |
| 35 | Relational model: route maintenance & upcoming-trip queries | `database/postgres/init/001_relational_baseline.sql`, `init/002_seed.sql`, `queries/003_queries.sql`, `docs/week35-lab.md`, `docs/week35-dossier.md`, `docs/week35-er-diagram.png` |
| 36 | SQL constraints & operations: ticketing integrity | `database/postgres/init/010_ticketing_draft.sql` (starter, unmodified), `init/011_ticketing_seed.sql`, `migrations/011_ticketing_integrity.sql`, `experiments/constraints_should_fail.sql`, `docs/week36-integrity-map.md` |
| 37 | SQL programmability: reporting logic | `database/postgres/queries/020_base_revenue.sql`, `migrations/020_reporting_function.sql`, `migrations/021_daily_revenue_trigger.sql`, `migrations/022_daily_captured_revenue.sql`, `experiments/reporting_cases.sql`, `docs/week37-reporting.md` |
| 38 | Schema migrations: product-identity change | `database/postgres/init/012_migration_fixture.sql`, `migrations/030-032_*.sql`, `experiments/lecture04/`, `docs/evidence/lecture04/README.md` |

## Compulsory Assignment 1 review guide

Group members: Emre Altintas & Justin Anthony Kapelke Jørgensen
Submitted commit: `647c1e2993e8b932f00c5c0d8902c5cc8f0c28e7`
Setup and reset instructions: [Setup](#setup)

### Where to find the work

Lecture 1: model, workload map and queries: [`docs/week35-dossier.md`](docs/week35-dossier.md) (system context, access-pattern map, ER diagram, functional dependency), [`init/001_relational_baseline.sql`](database/postgres/init/001_relational_baseline.sql), [`init/002_seed.sql`](database/postgres/init/002_seed.sql), [`queries/003_queries.sql`](database/postgres/queries/003_queries.sql), [`docs/week35-lab.md`](docs/week35-lab.md)

Lecture 2: constraints and tests: [`docs/week36-integrity-map.md`](docs/week36-integrity-map.md), [`migrations/011_ticketing_integrity.sql`](database/postgres/migrations/011_ticketing_integrity.sql), [`experiments/constraints_should_fail.sql`](database/postgres/experiments/constraints_should_fail.sql), [`init/010_ticketing_draft.sql`](database/postgres/init/010_ticketing_draft.sql) / [`011_ticketing_seed.sql`](database/postgres/init/011_ticketing_seed.sql)

Lecture 3: reporting experiment and comparison: [`docs/week37-reporting.md`](docs/week37-reporting.md), [`queries/020_base_revenue.sql`](database/postgres/queries/020_base_revenue.sql), [`migrations/020_reporting_function.sql`](database/postgres/migrations/020_reporting_function.sql), [`021_daily_revenue_trigger.sql`](database/postgres/migrations/021_daily_revenue_trigger.sql), [`022_daily_captured_revenue.sql`](database/postgres/migrations/022_daily_captured_revenue.sql), [`experiments/reporting_cases.sql`](database/postgres/experiments/reporting_cases.sql)

Lecture 4: migration stages and verification: [`docs/evidence/lecture04/README.md`](docs/evidence/lecture04/README.md), [`init/012_migration_fixture.sql`](database/postgres/init/012_migration_fixture.sql), [`migrations/030_expand_product_identity.sql`](database/postgres/migrations/030_expand_product_identity.sql) / [`031_backfill_ticket_product.sql`](database/postgres/migrations/031_backfill_ticket_product.sql) / [`032_require_ticket_product.sql`](database/postgres/migrations/032_require_ticket_product.sql), [`experiments/lecture04/`](database/postgres/experiments/lecture04/)

### Two decisions worth discussing

**Route-stop primary key: `(route_id, stop_id)`, not `(route_id, stop_sequence)`.** We chose the pair because in this slice a route calls at any stop at most once, so the pair already identifies the row, and `stop_sequence` becomes an attribute we constrain unique per route rather than part of the key. The alternative, keying on `(route_id, stop_sequence)`, would let a stop repeat on the same route (loop or out-and-back services), at the cost of no longer being able to ask "is this stop already on this route" without a separate scan. We picked the stricter key because none of MobilityTicketing's released routes loop back on themselves yet, and a stricter key catches a real modelling mistake instead of silently allowing it. See `docs/week35-dossier.md`, "Route-stop primary key" and "Assumption that may change later".

**Materialized view over a trigger-maintained table for daily captured revenue.** We built and compared four ways to answer "how much revenue did an operator capture on a given day": a direct query, a `STABLE` SQL function, an `AFTER INSERT` trigger writing into its own table, and a materialized view refreshed on demand. The trigger table was fastest to read but only ever grows on insert, it does not undo itself on a refund or a status change, and our own tests showed it starting from zero while the base data already held a payment, an unfixed backfill gap. We chose the materialized view instead, refreshed periodically, because reporting is explicitly the one workload in MobilityTicketing that can tolerate delay, unlike a purchase or a validation. See `docs/week37-reporting.md`, "Decision record" and its evidence log.

### One limitation or open question

Our constraints do not guarantee that a trip's `reserved_seats` never exceeds `capacity` under concurrent purchases. Two purchases for the last seat on the same trip, checked and written at nearly the same time, can both pass a plain `reserved_seats < capacity` check before either commits, and both succeed, overselling the trip. A `CHECK` constraint on the columns cannot close this gap by itself, it validates one row after the fact, not two competing writes against each other. Closing it needs an atomic `UPDATE ... WHERE reserved_seats < capacity` guarding the increment, a `SELECT ... FOR UPDATE` lock, or `SERIALIZABLE` isolation on the purchase transaction. This is recorded, not fixed, in `docs/week36-integrity-map.md`'s issue register. What we would check next: run two clients purchasing the same last seat at once and confirm whether the naive check-then-write actually oversells it in practice, before picking which of the three fixes to apply.
