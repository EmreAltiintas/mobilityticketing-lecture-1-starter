-- Third ticket, second product: gives week 38's product-identity migration
-- something real to migrate (>= 3 tickets covering >= 2 products), and a
-- deliberately discounted historical price (65 DKK) that differs from the
-- DAY product's current catalogue price (80 DKK) -- the migration must
-- preserve the price actually paid, never copy today's catalogue price.
insert into tickets (
    id, user_id, trip_id, ticket_code, status, product_code,
    valid_from_utc, valid_to_utc, price, currency
) values (
    'TICKET-3', 'USER-1', 'TRIP-M2-0720', 'CODE-DAY-0001', 'Active', 'DAY',
    '2026-09-01 00:00:00+00', '2026-09-02 00:00:00+00', 65.00, 'DKK'
)
on conflict do nothing;
