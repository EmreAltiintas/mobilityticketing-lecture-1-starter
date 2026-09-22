# MobilityTicketing

Databases for Developers (E2026) — weekly implementation labs on a fictional
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
tables and their seed). Constraint migrations are **not** run
automatically — apply them explicitly, in order:

```bash
docker compose exec -T postgres psql -U mobility -d mobility \
  < database/postgres/migrations/011_ticketing_integrity.sql
```

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
| 35 | Relational model: route maintenance & upcoming-trip queries | `database/postgres/init/001_relational_baseline.sql`, `init/002_seed.sql`, `queries/003_queries.sql`, `docs/week35-lab.md`, `docs/week35-dossier.md` |
| 36 | SQL constraints & operations: ticketing integrity | `database/postgres/init/010_ticketing_draft.sql` (starter, unmodified), `init/011_ticketing_seed.sql`, `migrations/011_ticketing_integrity.sql`, `experiments/constraints_should_fail.sql`, `docs/week36-integrity-map.md` |
| 37 | SQL programmability: reporting logic | `database/postgres/queries/020_base_revenue.sql`, `migrations/020_reporting_function.sql`, `migrations/021_daily_revenue_trigger.sql`, `migrations/022_daily_captured_revenue.sql`, `experiments/reporting_cases.sql`, `docs/week37-reporting.md` |
| 38 | Schema migrations: product-identity change | _pending_ |

## Compulsory Assignment 1 review guide

_To be completed in week 39 — see the assignment brief for the required
structure (submitted commit, where-to-find-the-work links, two decisions
worth discussing, one limitation/open question)._
