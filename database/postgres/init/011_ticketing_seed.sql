-- Add capacity and reserved-seat counts to the trips seeded in week 1
-- (database/postgres/init/002_seed.sql), instead of introducing a parallel
-- set of trip rows. TRIP-5C-0830 is cancelled, so it stays at zero capacity.
update trips set capacity = 120, reserved_seats = 2 where id = 'TRIP-M2-0700';
update trips set capacity = 120, reserved_seats = 0 where id = 'TRIP-M2-0720';
update trips set capacity = 80,  reserved_seats = 1 where id = 'TRIP-5C-0800';
update trips set capacity = 80,  reserved_seats = 0 where id = 'TRIP-5C-0830';

insert into products (code, name, price, currency) values
    ('SINGLE', 'Single trip', 36.00, 'DKK'),
    ('DAY', 'Day pass', 80.00, 'DKK')
on conflict do nothing;

insert into users (id, email, full_name, is_disabled) values
    ('USER-1', 'anna@example.test', 'Anna Jensen', false),
    ('USER-2', 'bo@example.test', 'Bo Nielsen', false)
on conflict do nothing;

insert into tickets (
    id, user_id, trip_id, ticket_code, status, product_code,
    valid_from_utc, valid_to_utc, price, currency
) values
    ('TICKET-1', 'USER-1', 'TRIP-M2-0700', 'CODE-M2-0001', 'Active', 'SINGLE',
        '2026-09-01 04:45:00+00', '2026-09-01 07:00:00+00', 36.00, 'DKK'),
    ('TICKET-2', 'USER-2', 'TRIP-5C-0800', 'CODE-5C-0001', 'Validated', 'SINGLE',
        '2026-09-01 05:45:00+00', '2026-09-01 08:00:00+00', 36.00, 'DKK')
on conflict do nothing;

insert into payments (
    id, user_id, ticket_id, external_payment_reference,
    amount, currency, status, created_utc
) values
    ('PAYMENT-1', 'USER-1', 'TICKET-1', 'gateway-capture-0001', 36.00, 'DKK', 'Captured', '2026-09-01 04:40:00+00'),
    ('PAYMENT-2', 'USER-2', 'TICKET-2', 'gateway-capture-0002', 36.00, 'DKK', 'Captured', '2026-09-01 05:40:00+00')
on conflict do nothing;

insert into validations (
    id, ticket_id, ticket_code, vehicle_id, stop_id, device_id,
    result, validated_utc
) values
    ('VALIDATION-1', 'TICKET-2', 'CODE-5C-0001', 'BUS-5C-01', 'STOP-CENTRAL', 'DEVICE-01',
        'Accepted', '2026-09-01 06:05:00+00')
on conflict do nothing;
