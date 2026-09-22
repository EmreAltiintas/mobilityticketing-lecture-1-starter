-- Deliberately incomplete, kept as supplied: this trigger only reacts to
-- INSERT on payments. It is applied as-is and its gaps are analysed with
-- real test cases in docs/week37-reporting.md rather than patched silently
-- (patching it here would remove the exact evidence the lab asks for).

create table daily_revenue_by_operator (
    operator_id text not null references operators(id),
    revenue_date date not null,
    captured_amount numeric not null default 0,
    captured_payments bigint not null default 0,
    primary key (operator_id, revenue_date)
);

create or replace function add_inserted_payment_to_daily_revenue()
returns trigger
language plpgsql
as $$
declare
    payment_operator_id text;
begin
    if new.status is distinct from 'Captured' then
        return new;
    end if;

    select r.operator_id
    into payment_operator_id
    from tickets t
    join trips tr on tr.id = t.trip_id
    join routes r on r.id = tr.route_id
    where t.id = new.ticket_id;

    insert into daily_revenue_by_operator (
        operator_id, revenue_date, captured_amount, captured_payments
    ) values (
        payment_operator_id, new.created_utc::date, new.amount, 1
    )
    on conflict (operator_id, revenue_date)
    do update set
        captured_amount = daily_revenue_by_operator.captured_amount + excluded.captured_amount,
        captured_payments = daily_revenue_by_operator.captured_payments + 1;

    return new;
end;
$$;

create trigger payments_daily_revenue_after_insert
after insert on payments
for each row
execute function add_inserted_payment_to_daily_revenue();

-- Known, documented gap (see docs/week37-reporting.md, issue register):
-- there is no AFTER UPDATE / AFTER DELETE trigger, so a status correction
-- (Failed->Captured, Captured->Refunded) or a delete of a payment row is
-- never reflected here. Extending this table to handle every transition
-- correctly is exactly the "hidden coupling" cost the lab asks us to weigh
-- against the other three approaches, not a bug to quietly fix.
