-- Step 9: the fully migrated writer. Uses only product_id -- no
-- product_code column exists on tickets any more, so this must not
-- reference it at all.

create or replace function insert_ticket_final(
    p_ticket_id text,
    p_user_id text,
    p_trip_id text,
    p_ticket_code text,
    p_status text,
    p_product_id uuid,
    p_valid_from timestamptz,
    p_valid_to timestamptz,
    p_price numeric,
    p_currency text
) returns void
language plpgsql
as $$
begin
    if not exists (select 1 from products where id = p_product_id) then
        raise exception 'Unknown product_id %', p_product_id;
    end if;

    insert into tickets (
        id, user_id, trip_id, ticket_code, status,
        product_id, valid_from_utc, valid_to_utc, price, currency
    ) values (
        p_ticket_id, p_user_id, p_trip_id, p_ticket_code, p_status,
        p_product_id, p_valid_from, p_valid_to, p_price, p_currency
    );
end;
$$;

select insert_ticket_final(
    'LAB04-FINAL-1', 'USER-1', 'TRIP-M2-0700', 'LAB04-CODE-FINAL-1', 'Active',
    (select id from products where code = 'SINGLE'),
    '2026-09-01 12:00:00+00', '2026-09-01 14:00:00+00', 36.00, 'DKK'
);

-- Run this file WHILE tickets.product_code still exists first (it works
-- fine -- the function never touches that column, so the NOT NULL on
-- product_code does not apply, it simply has no value supplied... check
-- whether that itself is a problem before product_code is actually
-- dropped, since a NOT NULL column with no default rejects a missing
-- value even from code that no longer cares about it).
