-- Run after applying migrations 020, 021 and 022, against a freshly
-- recreated container (docker compose down -v && docker compose up -d).
-- Each case below is followed by the SAME four comparison selects, so the
-- four approaches can be read side by side at every point rather than only
-- at the end. Compare 'direct query', 'function', 'materialized view (last
-- refresh)' and 'trigger table' after every case.

set timezone = 'UTC';

\echo '=== baseline (before any case) ==='
refresh materialized view daily_captured_revenue;

select 'direct query' as source, r.operator_id, p.created_utc::date as revenue_date,
       sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p
join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id
join routes r on r.id = tr.route_id
where p.status = 'Captured'
group by r.operator_id, p.created_utc::date
order by 2, 3;

select 'function' as source, 'OP-METRO' as operator_id, date '2026-09-01' as revenue_date,
       captured_amount, captured_payments
from captured_revenue_for_day('OP-METRO', '2026-09-01');

select 'materialized view' as source, operator_id, revenue_date, captured_amount, captured_payments
from daily_captured_revenue
order by operator_id, revenue_date;

select 'trigger table' as source, operator_id, revenue_date, captured_amount, captured_payments
from daily_revenue_by_operator
order by operator_id, revenue_date;

-- 1. Captured payment insert. All four should agree once refreshed --
-- except that the trigger table starts from zero (see issue 2 in
-- docs/week37-reporting.md: no initial backfill for pre-existing rows).
\echo '=== case 1: captured insert (+36) ==='
insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAY-CASE-CAPTURED', 'USER-1', 'TICKET-1', 'gateway-case-captured',
    36, 'DKK', 'Captured', '2026-09-01 10:00:00+00'
);
refresh materialized view daily_captured_revenue;
select 'direct query' as source, r.operator_id, p.created_utc::date as revenue_date,
       sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id join routes r on r.id = tr.route_id
where p.status = 'Captured' group by r.operator_id, p.created_utc::date order by 2, 3;
select 'trigger table' as source, operator_id, revenue_date, captured_amount, captured_payments
from daily_revenue_by_operator order by operator_id, revenue_date;

-- 2. Failed payment insert. Should not contribute anywhere.
\echo '=== case 2: failed insert (+50, ignored) ==='
insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAY-CASE-FAILED', 'USER-1', 'TICKET-1', 'gateway-case-failed',
    50, 'DKK', 'Failed', '2026-09-01 10:05:00+00'
);
refresh materialized view daily_captured_revenue;
select 'direct query' as source, r.operator_id, p.created_utc::date as revenue_date,
       sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id join routes r on r.id = tr.route_id
where p.status = 'Captured' group by r.operator_id, p.created_utc::date order by 2, 3;
select 'trigger table' as source, operator_id, revenue_date, captured_amount, captured_payments
from daily_revenue_by_operator order by operator_id, revenue_date;

-- 3. Status correction Failed -> Captured. Direct query/function/view
-- should include it; the trigger table should NOT (no AFTER UPDATE).
\echo '=== case 3: Failed -> Captured correction (+50) ==='
update payments set status = 'Captured' where id = 'PAY-CASE-FAILED';
refresh materialized view daily_captured_revenue;
select 'direct query' as source, r.operator_id, p.created_utc::date as revenue_date,
       sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id join routes r on r.id = tr.route_id
where p.status = 'Captured' group by r.operator_id, p.created_utc::date order by 2, 3;
select 'trigger table' as source, operator_id, revenue_date, captured_amount, captured_payments
from daily_revenue_by_operator order by operator_id, revenue_date;

-- 4. Status correction Captured -> Refunded (case 1's payment). Direct
-- query/function/view should exclude it; the trigger table should still
-- show it as Captured.
\echo '=== case 4: Captured -> Refunded (-36) ==='
update payments set status = 'Refunded' where id = 'PAY-CASE-CAPTURED';
refresh materialized view daily_captured_revenue;
select 'direct query' as source, r.operator_id, p.created_utc::date as revenue_date,
       sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id join routes r on r.id = tr.route_id
where p.status = 'Captured' group by r.operator_id, p.created_utc::date order by 2, 3;
select 'trigger table' as source, operator_id, revenue_date, captured_amount, captured_payments
from daily_revenue_by_operator order by operator_id, revenue_date;

-- 5. Delete the (now Captured) former-failed payment.
\echo '=== case 5: delete the now-Captured former-failed payment (-50) ==='
delete from payments where id = 'PAY-CASE-FAILED';
refresh materialized view daily_captured_revenue;
select 'direct query' as source, r.operator_id, p.created_utc::date as revenue_date,
       sum(p.amount) as captured_amount, count(*) as captured_payments
from payments p join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id join routes r on r.id = tr.route_id
where p.status = 'Captured' group by r.operator_id, p.created_utc::date order by 2, 3;
select 'trigger table' as source, operator_id, revenue_date, captured_amount, captured_payments
from daily_revenue_by_operator order by operator_id, revenue_date;

-- 6. Duplicate delivery of an already-captured external payment reference.
-- Expect this INSERT to be rejected by the week-36 constraint
-- payments_external_reference_captured_unique before any of the four
-- reporting approaches ever see a new row.
\echo '=== case 6: duplicate external_payment_reference (expect rejection) ==='
insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values (
    'PAY-CASE-DUPLICATE', 'USER-1', 'TICKET-1', 'gateway-capture-0001',
    36, 'DKK', 'Captured', '2026-09-01 10:10:00+00'
);
