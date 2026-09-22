insert into operators (id, name) values
    ('OP-METRO', 'City Metro'),
    ('OP-BUS', 'City Bus')
on conflict do nothing;

insert into routes (id, operator_id, city_id, mode, short_name) values
    ('LINE-M2', 'OP-METRO', 'CPH', 'metro', 'M2'),
    ('LINE-5C', 'OP-BUS', 'CPH', 'bus', '5C')
on conflict do nothing;

insert into stops (id, city_id, name) values
    ('STOP-NORREPORT', 'CPH', 'Nørreport'),
    ('STOP-KONGENS-NYTORV', 'CPH', 'Kongens Nytorv'),
    ('STOP-AIRPORT', 'CPH', 'Copenhagen Airport'),
    ('STOP-CENTRAL', 'CPH', 'Copenhagen Central Station')
on conflict do nothing;

-- route_stops key is (route_id, stop_id): a route visits each stop once, and
-- stop_sequence gives the visiting order.
insert into route_stops (route_id, stop_id, stop_sequence) values
    ('LINE-M2', 'STOP-NORREPORT', 1),
    ('LINE-M2', 'STOP-KONGENS-NYTORV', 2),
    ('LINE-M2', 'STOP-AIRPORT', 3),
    ('LINE-5C', 'STOP-CENTRAL', 1),
    ('LINE-5C', 'STOP-NORREPORT', 2),
    ('LINE-5C', 'STOP-KONGENS-NYTORV', 3)
on conflict do nothing;

-- Two trips per route on service date 2026-09-01.
-- Copenhagen is UTC+2 (CEST) on that date, so 07:00 local is 05:00 UTC.
insert into trips (id, route_id, service_date, scheduled_departure_utc, status) values
    ('TRIP-M2-0700', 'LINE-M2', date '2026-09-01', timestamptz '2026-09-01 05:00:00+00', 'scheduled'),
    ('TRIP-M2-0720', 'LINE-M2', date '2026-09-01', timestamptz '2026-09-01 05:20:00+00', 'scheduled'),
    ('TRIP-5C-0800', 'LINE-5C', date '2026-09-01', timestamptz '2026-09-01 06:00:00+00', 'scheduled'),
    ('TRIP-5C-0830', 'LINE-5C', date '2026-09-01', timestamptz '2026-09-01 06:30:00+00', 'cancelled')
on conflict do nothing;
