-- Migration 011: ticketing integrity
--
-- Adds the constraints that database/postgres/init/010_ticketing_draft.sql
-- deliberately omits. 010_ticketing_draft.sql is not modified; every rule
-- here is additive, so it can be re-applied to a fresh database on top of
-- the init scripts.
--
-- Apply with:
--   docker compose exec -T postgres psql -U mobility -d mobility \
--     < database/postgres/migrations/011_ticketing_integrity.sql
--
-- See docs/week36-integrity-map.md for the reasoning behind each rule and
-- for the invariants this migration deliberately does NOT enforce.

begin;

-- ---------------------------------------------------------------------------
-- trips: capacity and reserved seats
-- ---------------------------------------------------------------------------
alter table trips
    alter column capacity set not null,
    alter column reserved_seats set not null,
    add constraint trips_capacity_non_negative
        check (capacity >= 0),
    add constraint trips_reserved_seats_valid
        check (reserved_seats between 0 and capacity);

-- ---------------------------------------------------------------------------
-- products
-- ---------------------------------------------------------------------------
alter table products
    alter column name set not null,
    alter column price set not null,
    alter column currency set not null,
    add constraint products_price_non_negative
        check (price >= 0),
    add constraint products_currency_iso4217
        check (currency ~ '^[A-Z]{3}$');

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
alter table users
    alter column email set not null,
    alter column full_name set not null,
    alter column is_disabled set not null,
    add constraint users_email_unique
        unique (email);

-- ---------------------------------------------------------------------------
-- tickets
-- ---------------------------------------------------------------------------
alter table tickets
    alter column user_id set not null,
    alter column trip_id set not null,
    alter column ticket_code set not null,
    alter column status set not null,
    alter column product_code set not null,
    alter column valid_from_utc set not null,
    alter column valid_to_utc set not null,
    alter column price set not null,
    alter column currency set not null,
    add constraint tickets_user_fk
        foreign key (user_id) references users(id),
    add constraint tickets_trip_fk
        foreign key (trip_id) references trips(id),
    add constraint tickets_product_fk
        foreign key (product_code) references products(code),
    add constraint tickets_ticket_code_unique
        unique (ticket_code),
    -- Lets validations carry both ticket_id and ticket_code and have the pair
    -- checked together (see validations_ticket_fk below), instead of trusting
    -- every writer to keep the two in sync.
    add constraint tickets_id_ticket_code_unique
        unique (id, ticket_code),
    add constraint tickets_valid_window
        check (valid_to_utc >= valid_from_utc),
    add constraint tickets_price_non_negative
        check (price >= 0),
    add constraint tickets_currency_iso4217
        check (currency ~ '^[A-Z]{3}$'),
    add constraint tickets_status_allowed
        check (status in ('Active', 'Validated', 'Expired', 'Cancelled', 'Refunded'));

-- ---------------------------------------------------------------------------
-- payments
-- ---------------------------------------------------------------------------
alter table payments
    alter column user_id set not null,
    alter column ticket_id set not null,
    alter column amount set not null,
    alter column currency set not null,
    alter column status set not null,
    add constraint payments_user_fk
        foreign key (user_id) references users(id),
    add constraint payments_ticket_fk
        foreign key (ticket_id) references tickets(id),
    add constraint payments_amount_non_negative
        check (amount >= 0),
    add constraint payments_currency_iso4217
        check (currency ~ '^[A-Z]{3}$'),
    add constraint payments_status_allowed
        check (status in ('Captured', 'Pending', 'Failed', 'Refunded'));

-- A CAPTURED payment's external reference must be unique: the same captured
-- charge should never be recorded twice. A failed or pending attempt may
-- reuse a reference on retry, so the rule is scoped to captured rows rather
-- than a table-wide UNIQUE column (see docs/week36-integrity-map.md).
create unique index payments_external_reference_captured_unique
    on payments (external_payment_reference)
    where status = 'Captured';

-- ---------------------------------------------------------------------------
-- validations
-- ---------------------------------------------------------------------------
alter table validations
    alter column ticket_id set not null,
    alter column ticket_code set not null,
    alter column result set not null,
    -- A validation must name the same ticket by id and by code: the composite
    -- foreign key rejects a validation whose ticket_id and ticket_code belong
    -- to two different tickets.
    add constraint validations_ticket_fk
        foreign key (ticket_id, ticket_code) references tickets(id, ticket_code),
    add constraint validations_result_allowed
        check (result in ('Accepted', 'Rejected'));

commit;
