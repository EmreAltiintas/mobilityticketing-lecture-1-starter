-- A function centralises the read logic but does not store an aggregate
-- result: every call re-reads the base tables, so it is exactly as fresh
-- and exactly as expensive as the direct query in queries/020_base_revenue.sql.

create or replace function captured_revenue_for_day(
    requested_operator_id text,
    requested_date date
)
returns table (
    captured_amount numeric,
    captured_payments bigint
)
language sql
stable
as $$
    select
        coalesce(sum(p.amount), 0),
        count(*)
    from payments p
    join tickets t on t.id = p.ticket_id
    join trips tr on tr.id = t.trip_id
    join routes r on r.id = tr.route_id
    where r.operator_id = requested_operator_id
      and p.created_utc::date = requested_date
      and p.status = 'Captured';
$$;
