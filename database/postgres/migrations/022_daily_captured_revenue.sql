-- A materialized view: fast to read, but a frozen snapshot from the last
-- REFRESH. Created WITH NO DATA, so it must be refreshed once before its
-- first read (a read before that fails with "materialized view has not
-- been populated" rather than returning zero rows).

create materialized view daily_captured_revenue as
select
    r.operator_id,
    p.created_utc::date as revenue_date,
    sum(p.amount) as captured_amount,
    count(*) as captured_payments
from payments p
join tickets t on t.id = p.ticket_id
join trips tr on tr.id = t.trip_id
join routes r on r.id = tr.route_id
where p.status = 'Captured'
group by r.operator_id, p.created_utc::date
with no data;

create unique index daily_captured_revenue_key
    on daily_captured_revenue (operator_id, revenue_date);

-- Run explicitly whenever the source data should become visible here:
-- refresh materialized view daily_captured_revenue;
