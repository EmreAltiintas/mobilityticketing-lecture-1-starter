-- Step 4: represents an application instance that HAS been rewritten to
-- purchase by product_id. It still writes product_code (until step 9),
-- but derives it from the product row rather than trusting a caller --
-- an unrelated/mismatched supplied code is rejected, not silently stored.

create or replace function insert_ticket_by_product_id(
    p_ticket_id text,
    p_user_id text,
    p_trip_id text,
    p_ticket_code text,
    p_status text,
    p_product_id uuid,
    p_supplied_product_code text,  -- what the caller *claims* the code is; may be null
    p_valid_from timestamptz,
    p_valid_to timestamptz,
    p_price numeric,               -- the agreed purchase price -- never the catalogue price
    p_currency text
) returns void
language plpgsql
as $$
declare
    resolved_code text;
begin
    select code into resolved_code from products where id = p_product_id;
    if resolved_code is null then
        raise exception 'Unknown product_id %', p_product_id;
    end if;

    if p_supplied_product_code is not null
       and p_supplied_product_code is distinct from resolved_code then
        raise exception
            'Supplied product_code % does not match product_id % (resolves to %) -- rejected',
            p_supplied_product_code, p_product_id, resolved_code;
    end if;

    insert into tickets (
        id, user_id, trip_id, ticket_code, status,
        product_code, product_id,
        valid_from_utc, valid_to_utc, price, currency
    ) values (
        p_ticket_id, p_user_id, p_trip_id, p_ticket_code, p_status,
        resolved_code, p_product_id,
        p_valid_from, p_valid_to, p_price, p_currency
    );
end;
$$;

-- Product IDs available to purchase against.
select id, code, price, currency from products order by code;

-- A normal new-style purchase: only the ID is supplied.
select insert_ticket_by_product_id(
    'LAB04-NEW-1', 'USER-1', 'TRIP-M2-0700', 'LAB04-CODE-NEW-1', 'Active',
    (select id from products where code = 'SINGLE'), null,
    '2026-09-01 12:00:00+00', '2026-09-01 14:00:00+00', 36.00, 'DKK'
);

-- A caller that supplies a MATCHING code: allowed.
select insert_ticket_by_product_id(
    'LAB04-NEW-2', 'USER-2', 'TRIP-5C-0800', 'LAB04-CODE-NEW-2', 'Active',
    (select id from products where code = 'DAY'), 'DAY',
    '2026-09-01 09:00:00+00', '2026-09-02 09:00:00+00', 80.00, 'DKK'
);

-- A caller that supplies a MISMATCHED code (product_id resolves to SINGLE,
-- claimed code is DAY): the database-level check inside the function
-- rejects it. Run inside a transaction and roll back so the attempt
-- leaves no row behind.
begin;
select insert_ticket_by_product_id(
    'LAB04-NEW-MISMATCH', 'USER-1', 'TRIP-M2-0700', 'LAB04-CODE-MISMATCH', 'Active',
    (select id from products where code = 'SINGLE'), 'DAY',
    '2026-09-01 12:00:00+00', '2026-09-01 14:00:00+00', 36.00, 'DKK'
);
rollback;
