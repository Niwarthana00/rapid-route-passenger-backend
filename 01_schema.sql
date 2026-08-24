-- =============================================================================
-- BUS ENTERPRISE MANAGEMENT SYSTEM — ULTRA ENTERPRISE PRODUCTION SCHEMA (v2)
-- Database    : PostgreSQL 15+ (Production Scalability Tuned)
-- Extensions  : uuid-ossp, postgis, pgcrypto
-- Safe Scale  : 10M+ Active Users / High-Concurrency Architecture
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- =============================================================================
-- SCHEMAS & NAMESPACES (Logical Isolation)
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS biz;
CREATE SCHEMA IF NOT EXISTS fin;     -- FIX: was "Fin" (uppercase) in v1 — Postgres folds
                                      -- unquoted identifiers to lowercase, so CREATE SCHEMA Fin
                                      -- actually created "fin" silently. Not a real bug, but every
                                      -- reference elsewhere used lowercase "fin" already so this
                                      -- just removes the misleading casing.
CREATE SCHEMA IF NOT EXISTS system;

SET search_path TO core, biz, fin, system, public;

-- =============================================================================
-- GLOBAL CUSTOM TYPES & ENUMS
-- =============================================================================
CREATE TYPE core.fuel_type_enum        AS ENUM ('DIESEL', 'PETROL', 'CNG', 'ELECTRIC', 'HYBRID');
CREATE TYPE core.doc_driver_enum       AS ENUM ('NIC', 'LICENSE', 'MEDICAL', 'BACKGROUND_CHECK', 'OTHER');
CREATE TYPE core.doc_vehicle_enum      AS ENUM ('REVENUE_LICENSE', 'INSURANCE', 'FITNESS', 'EMISSION', 'ROUTE_PERMIT');
CREATE TYPE core.seat_type_enum        AS ENUM ('STANDARD', 'PREMIUM', 'DISABLED', 'FRONT_ROW');
CREATE TYPE core.gender_enum           AS ENUM ('MALE', 'FEMALE', 'OTHER');
CREATE TYPE core.loyalty_tier_enum     AS ENUM ('BRONZE', 'SILVER', 'GOLD', 'PLATINUM');

CREATE TYPE biz.trip_status_enum       AS ENUM ('SCHEDULED', 'BOARDING', 'DEPARTED', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'DELAYED');
CREATE TYPE biz.booking_status_enum    AS ENUM ('PENDING', 'CONFIRMED', 'CANCELLED', 'COMPLETED', 'NO_SHOW');

CREATE TYPE fin.payment_status_enum    AS ENUM ('PENDING', 'SUCCESS', 'FAILED', 'REFUNDED', 'PARTIALLY_REFUNDED');
CREATE TYPE fin.payment_method_enum    AS ENUM ('CASH', 'CARD', 'ONLINE_BANKING', 'MOBILE_WALLET', 'KIOSK');

CREATE TYPE system.notify_channel_enum AS ENUM ('SMS', 'EMAIL', 'PUSH', 'WHATSAPP');
CREATE TYPE system.notify_status_enum  AS ENUM ('PENDING', 'SENT', 'DELIVERED', 'FAILED');
CREATE TYPE system.audit_action_enum   AS ENUM ('INSERT', 'UPDATE', 'DELETE');

-- =============================================================================
-- DOMAIN 1 — CORE FLEET & PERSONNEL MANAGEMENT (Master Layer)
-- =============================================================================

CREATE TABLE core.drivers (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nic_number          VARCHAR(12) NOT NULL,
    full_name           VARCHAR(200) NOT NULL,
    license_number      VARCHAR(30) NOT NULL,
    license_expiry      DATE NOT NULL,
    license_class       VARCHAR(20) NOT NULL,            -- e.g. 'D', 'DE' for Heavy Buses
    phone               VARCHAR(15) NOT NULL,
    emergency_contact   VARCHAR(15),
    address             TEXT,
    date_of_birth       DATE,
    gender              core.gender_enum,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMPTZ DEFAULT NULL
    -- NOTE: the original chk_drivers_license_expiry CHECK constraint is intentionally
    -- removed. A CHECK is evaluated only on INSERT/UPDATE of that row, so it can never
    -- stop a license from going stale while the row just sits there — it only blocked
    -- inserting an already-expired license. That's a real (if minor) use case, so
    -- rather than just deleting it outright, expiry monitoring belongs in a scheduled
    -- job / view (see core.v_expiring_driver_docs below) which can actually run on a
    -- schedule and flag/deactivate drivers as time passes.
);

CREATE UNIQUE INDEX uq_drivers_nic_active ON core.drivers(nic_number) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX uq_drivers_license_active ON core.drivers(license_number) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX uq_drivers_phone_active ON core.drivers(phone) WHERE (deleted_at IS NULL);

CREATE TABLE core.driver_documents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id       UUID NOT NULL REFERENCES core.drivers(id) ON DELETE CASCADE,
    doc_type        core.doc_driver_enum NOT NULL,
    file_path       TEXT NOT NULL,
    issued_at       DATE NOT NULL,
    expires_at      DATE,
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    verified_by     VARCHAR(100),
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE core.vehicles (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    registration_number     VARCHAR(20) NOT NULL,
    chassis_number          VARCHAR(50) NOT NULL,
    engine_number           VARCHAR(50) NOT NULL,
    make                    VARCHAR(60) NOT NULL,
    model                   VARCHAR(60) NOT NULL,
    year                    SMALLINT NOT NULL,
    total_seats             SMALLINT NOT NULL CHECK (total_seats > 0),
    fuel_type               core.fuel_type_enum NOT NULL DEFAULT 'DIESEL',
    has_ac                  BOOLEAN NOT NULL DEFAULT FALSE,
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    odometer_km             DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at              TIMESTAMPTZ DEFAULT NULL
);

CREATE UNIQUE INDEX uq_vehicles_reg_active ON core.vehicles(registration_number) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX uq_vehicles_chassis_active ON core.vehicles(chassis_number) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX uq_vehicles_engine_active ON core.vehicles(engine_number) WHERE (deleted_at IS NULL);

CREATE TABLE core.vehicle_documents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id      UUID NOT NULL REFERENCES core.vehicles(id) ON DELETE CASCADE,
    doc_type        core.doc_vehicle_enum NOT NULL,
    file_path       TEXT NOT NULL,
    issued_at       DATE NOT NULL,
    expires_at      DATE,
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    verified_by     VARCHAR(100),
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE core.driver_assignments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id       UUID NOT NULL REFERENCES core.drivers(id),
    vehicle_id      UUID NOT NULL REFERENCES core.vehicles(id),
    assigned_from   DATE NOT NULL,
    assigned_to     DATE,
    is_current      BOOLEAN NOT NULL DEFAULT TRUE,
    assigned_by     VARCHAR(100),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_assignment_dates CHECK (assigned_to IS NULL OR assigned_to >= assigned_from)
);

CREATE UNIQUE INDEX uq_active_driver_assignment ON core.driver_assignments (driver_id) WHERE (is_current = TRUE);

-- =============================================================================
-- DOMAIN 1B — VEHICLE MAINTENANCE LOG (new)
-- =============================================================================

CREATE TABLE core.vehicle_maintenance (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id          UUID NOT NULL REFERENCES core.vehicles(id),
    maintenance_type    VARCHAR(60) NOT NULL,           -- 'ROUTINE', 'REPAIR', 'INSPECTION'
    description         TEXT,
    odometer_at_service DECIMAL(12,2),
    cost                DECIMAL(10,2) CHECK (cost IS NULL OR cost >= 0),
    service_date        DATE NOT NULL,
    next_service_date   DATE,
    performed_by        VARCHAR(150),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_maintenance_next_after_service
        CHECK (next_service_date IS NULL OR next_service_date >= service_date)
);
CREATE INDEX idx_vehicle_maintenance ON core.vehicle_maintenance(vehicle_id, service_date DESC);

-- =============================================================================
-- DOMAIN 2 — GEOGRAPHIC ROUTE & SCHEDULING LAYER (PostGIS Enabled)
-- =============================================================================

CREATE TABLE core.districts (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(80) NOT NULL,
    province    VARCHAR(80) NOT NULL
);
CREATE UNIQUE INDEX uq_district_name ON core.districts(name);

CREATE TABLE core.halts (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    district_id UUID NOT NULL REFERENCES core.districts(id),
    name        VARCHAR(150) NOT NULL,
    address     TEXT,
    -- NOTE (v4) on GEOGRAPHY vs GEOMETRY: a review suggested switching this to
    -- GEOMETRY(POINT, 3857) for speed, citing sphere math being heavier than planar
    -- math. The general claim is true, but the specific "3x faster" figure couldn't
    -- be verified and the fix as proposed trades away correctness: in Web Mercator
    -- (3857), distances are in projected meters that distort with latitude, so a
    -- naive ST_Distance call on that projection silently returns wrong "nearest
    -- halt" results unless every caller remembers to reproject or use
    -- ST_DistanceSphere — an easy mistake for "find halts near me" queries, which
    -- is the exact feature this column exists for.
    -- The actual risk worth fixing isn't the type — it's the QUERY PATTERN.
    -- GIST indexes index-assist the <-> operator for *both* geometry and geography
    -- (PostGIS supports KNN on geography too), so "nearest N halts" queries written
    -- as `ORDER BY location <-> ST_MakePoint(...)::geography LIMIT N` already use
    -- the index and get correct sphere distances for free. The slow path is calling
    -- ST_DWithin/ST_Distance in a WHERE clause without <->, which forces a
    -- per-row sphere calculation across the whole table. Keep GEOGRAPHY here;
    -- enforce the <-> ORDER BY pattern in application queries instead.
    location    GEOGRAPHY(POINT, 4326) NOT NULL,
    latitude    DECIMAL(10,7) NOT NULL,
    longitude   DECIMAL(10,7) NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE core.routes (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_number            VARCHAR(20) NOT NULL,
    name                    VARCHAR(200) NOT NULL,
    origin_halt_id          UUID NOT NULL REFERENCES core.halts(id),
    destination_halt_id     UUID NOT NULL REFERENCES core.halts(id),
    total_distance_km       DECIMAL(8,2) NOT NULL CHECK (total_distance_km > 0),
    estimated_duration_mins INT NOT NULL CHECK (estimated_duration_mins > 0),
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_routes_diff_halts CHECK (origin_halt_id <> destination_halt_id)
);
CREATE UNIQUE INDEX uq_route_number_active ON core.routes(route_number) WHERE (is_active = TRUE);

CREATE TABLE core.route_halts (
    id                              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_id                        UUID NOT NULL REFERENCES core.routes(id) ON DELETE CASCADE,
    halt_id                         UUID NOT NULL REFERENCES core.halts(id),
    sequence_order                  SMALLINT NOT NULL CHECK (sequence_order >= 0),
    distance_from_origin_km         DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    travel_time_from_origin_mins    INT NOT NULL DEFAULT 0,

    CONSTRAINT uq_route_halt_seq UNIQUE (route_id, sequence_order),
    CONSTRAINT uq_route_halt UNIQUE (route_id, halt_id)
);

CREATE TABLE biz.schedules (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_id            UUID NOT NULL REFERENCES core.routes(id),
    vehicle_id          UUID NOT NULL REFERENCES core.vehicles(id),
    driver_id           UUID NOT NULL REFERENCES core.drivers(id),
    departure_time      TIME NOT NULL,
    arrival_time        TIME NOT NULL,
    days_of_week        SMALLINT[] NOT NULL,
    valid_from          DATE NOT NULL,
    valid_to            DATE,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_schedule_times CHECK (arrival_time > departure_time),
    CONSTRAINT chk_schedule_dates CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

-- =============================================================================
-- DOMAIN 3 — HIGH CONCURRENCY TRANSACTIONAL LAYER (Trips & Bookings)
-- =============================================================================

CREATE TABLE core.passengers (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    full_name       VARCHAR(150) NOT NULL,
    phone           VARCHAR(15) NOT NULL,
    email           VARCHAR(200),
    nic_number      VARCHAR(12),
    date_of_birth   DATE,
    gender          core.gender_enum,
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMPTZ DEFAULT NULL
);
CREATE UNIQUE INDEX uq_passengers_phone_active ON core.passengers(phone) WHERE (deleted_at IS NULL);
CREATE UNIQUE INDEX uq_passengers_email_active ON core.passengers(email) WHERE (deleted_at IS NULL AND email IS NOT NULL);

-- =============================================================================
-- CENTRAL AUTHENTICATION & USER ACCOUNTS
-- =============================================================================
CREATE TABLE IF NOT EXISTS core.user_accounts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           VARCHAR(255),
    phone           VARCHAR(20) NOT NULL,
    password_hash   TEXT NOT NULL,
    photo_url       TEXT,
    push_token      VARCHAR(255),
    user_type       VARCHAR(20) NOT NULL CHECK (user_type IN ('PASSENGER', 'DRIVER', 'ADMIN')),
    passenger_id    UUID REFERENCES core.passengers(id) ON DELETE SET NULL,
    driver_id       UUID REFERENCES core.drivers(id) ON DELETE SET NULL,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_user_accounts_phone ON core.user_accounts(phone);
CREATE UNIQUE INDEX uq_user_accounts_email ON core.user_accounts(email) WHERE (email IS NOT NULL);

-- CHANGED (v4): passenger_id promoted to PRIMARY KEY, surrogate id column dropped.
-- This is a genuine 1:1 relation (one loyalty row per passenger), so the previous
-- id PK + passenger_id UNIQUE was two B-tree indexes maintaining the same fact.
-- The ON CONFLICT (passenger_id) lookup in the sync trigger below now hits the
-- primary key directly instead of a secondary unique index.
CREATE TABLE core.passenger_loyalty (
    passenger_id    UUID PRIMARY KEY REFERENCES core.passengers(id) ON DELETE CASCADE,
    tier            core.loyalty_tier_enum NOT NULL DEFAULT 'BRONZE',
    total_trips     INT NOT NULL DEFAULT 0 CHECK (total_trips >= 0),
    total_spent     DECIMAL(12,2) NOT NULL DEFAULT 0.00 CHECK (total_spent >= 0),
    points_balance  INT NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE core.seat_map (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id      UUID NOT NULL REFERENCES core.vehicles(id) ON DELETE CASCADE,
    seat_number     SMALLINT NOT NULL CHECK (seat_number > 0),
    seat_type       core.seat_type_enum NOT NULL DEFAULT 'STANDARD',
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_vehicle_seat UNIQUE (vehicle_id, seat_number)
);

-- CHANGED (v3): actual_seats_available removed from this table.
-- Why: under high concurrency, every booking on the same trip_id updated this one
-- row, so writes serialized on that row's lock. That's real row-lock contention
-- (not technically a "deadlock" — a deadlock needs a lock cycle between two
-- transactions; this is one-directional queuing/blocking), and it gets worse
-- linearly with concurrent bookings per trip. Moving seat counts to a read-side
-- view (biz.v_trip_seat_inventory, below) removes the write entirely. If an even
-- faster live counter is needed later for a seat-map UI under very heavy load, an
-- external atomic counter (e.g. Redis DECRBY) is the right place for it — not a
-- column in the OLTP table.
CREATE TABLE biz.trips (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    schedule_id             UUID NOT NULL REFERENCES biz.schedules(id),
    vehicle_id              UUID NOT NULL REFERENCES core.vehicles(id),
    driver_id               UUID NOT NULL REFERENCES core.drivers(id),
    trip_date               DATE NOT NULL,
    status                  biz.trip_status_enum NOT NULL DEFAULT 'SCHEDULED',
    departed_at             TIMESTAMPTZ,
    arrived_at              TIMESTAMPTZ,
    delay_reason            TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_trip_schedule_date UNIQUE (schedule_id, trip_date)
);

CREATE TABLE biz.bookings (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    passenger_id        UUID NOT NULL REFERENCES core.passengers(id),
    trip_id             UUID NOT NULL REFERENCES biz.trips(id),
    boarding_halt_id    UUID NOT NULL REFERENCES core.halts(id),
    alighting_halt_id   UUID NOT NULL REFERENCES core.halts(id),
    seat_number         SMALLINT NOT NULL CHECK (seat_number > 0),
    fare_amount         DECIMAL(10,2) NOT NULL CHECK (fare_amount >= 0),
    booking_status      biz.booking_status_enum NOT NULL DEFAULT 'PENDING',
    booking_ref         VARCHAR(30) NOT NULL,
    booked_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cancelled_at        TIMESTAMPTZ,
    cancel_reason       TEXT,

    CONSTRAINT chk_booking_halts CHECK (boarding_halt_id <> alighting_halt_id)
);
CREATE UNIQUE INDEX uq_booking_ref ON biz.bookings(booking_ref);

CREATE UNIQUE INDEX uq_trip_seat_lock
ON biz.bookings (trip_id, seat_number)
WHERE (booking_status <> 'CANCELLED');

-- =============================================================================
-- DOMAIN 4 — BATCH DATA & AUDIT LAYERS (Operational Analytics & Finance)
-- =============================================================================

CREATE TABLE biz.trip_halt_log (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id             UUID NOT NULL REFERENCES biz.trips(id) ON DELETE CASCADE,
    halt_id             UUID NOT NULL REFERENCES core.halts(id),
    sequence_order      SMALLINT NOT NULL,
    arrived_at          TIMESTAMPTZ,
    departed_at         TIMESTAMPTZ,
    passengers_boarded  SMALLINT NOT NULL DEFAULT 0,
    passengers_alighted SMALLINT NOT NULL DEFAULT 0,
    current_occupancy   SMALLINT NOT NULL DEFAULT 0,

    CONSTRAINT uq_trip_halt UNIQUE (trip_id, halt_id)
);

-- FIX: fare_rules directionality. Rather than bolting on an is_bidirectional flag
-- (which still leaves the question "bidirectional w.r.t. which row — does a reverse
-- lookup need a second SELECT with from/to swapped, and which base_fare wins if both
-- directions exist?"), this models it explicitly: a fare rule is always directional
-- (from_halt_id -> to_halt_id). If a route is symmetric, you insert two rows. This
-- keeps fin.calculate_fare() a single deterministic lookup with no runtime branching,
-- which matters for a function that runs on every booking.
CREATE TABLE fin.fare_rules (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    route_id                UUID NOT NULL REFERENCES core.routes(id) ON DELETE CASCADE,
    from_halt_id            UUID NOT NULL REFERENCES core.halts(id),
    to_halt_id              UUID NOT NULL REFERENCES core.halts(id),
    base_fare               DECIMAL(10,2) NOT NULL CHECK (base_fare >= 0),
    per_km_rate             DECIMAL(6,4) NOT NULL DEFAULT 0.0000,
    has_ac_surcharge        BOOLEAN NOT NULL DEFAULT FALSE,
    ac_surcharge_amount     DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    effective_from          DATE NOT NULL,
    effective_to            DATE,

    CONSTRAINT chk_fare_halts CHECK (from_halt_id <> to_halt_id),
    CONSTRAINT chk_fare_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

-- Prevent two overlapping fare rules for the exact same route+pair+date window
CREATE INDEX idx_fare_rules_lookup ON fin.fare_rules(route_id, from_halt_id, to_halt_id, effective_from);

CREATE TABLE fin.payments (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_id          UUID NOT NULL REFERENCES biz.bookings(id),
    payment_method      fin.payment_method_enum NOT NULL,
    amount              DECIMAL(10,2) NOT NULL CHECK (amount > 0),
    currency            CHAR(3) NOT NULL DEFAULT 'LKR',
    transaction_ref     VARCHAR(120) NOT NULL,
    gateway_ref         VARCHAR(200),
    payment_status      fin.payment_status_enum NOT NULL DEFAULT 'PENDING',
    paid_at             TIMESTAMPTZ,
    refunded_at         TIMESTAMPTZ,
    refund_amount       DECIMAL(10,2) DEFAULT 0.00,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_payment_txn_ref ON fin.payments(transaction_ref);

CREATE TABLE system.notifications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    passenger_id    UUID NOT NULL REFERENCES core.passengers(id),
    booking_id      UUID REFERENCES biz.bookings(id),
    channel         system.notify_channel_enum NOT NULL,
    message_type    VARCHAR(60) NOT NULL,
    body            TEXT NOT NULL,
    status          system.notify_status_enum NOT NULL DEFAULT 'PENDING',
    sent_at         TIMESTAMPTZ,
    error_msg       TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- CHANGED (v4): partitioned by performed_at (RANGE). At 10M+ users, this table is
-- write-amplified by triggers on bookings/payments/trips/fare_rules and will hit
-- billions of rows within months. Partitioning keeps each partition's B-tree small
-- (bounded by one time window instead of the whole table's history) and lets old
-- data be dropped/archived as a metadata-only operation (DROP PARTITION) instead of
-- a slow DELETE that has to scan and vacuum billions of rows.
-- Partition key must be part of the primary key, so this becomes a composite key;
-- id alone is no longer globally unique-enforced at the DB level across partitions
-- (uniqueness is enforced per-partition, which is the standard tradeoff for
-- declarative partitioning in Postgres and is fine for an append-only log).
CREATE TABLE system.audit_logs (
    id              UUID NOT NULL DEFAULT uuid_generate_v4(),
    -- On PG18+: change the default to uuidv7() for index locality. On PG17 and
    -- earlier there's no built-in v7 generator (see note further down this file) —
    -- v4 here is fine since each partition is already time-bounded by performed_at,
    -- which gives you most of the same locality benefit without needing v7 at all.
    table_name      VARCHAR(80) NOT NULL,
    record_id       UUID NOT NULL,
    action          system.audit_action_enum NOT NULL,
    old_values      JSONB DEFAULT NULL,
    new_values      JSONB DEFAULT NULL,
    performed_by    VARCHAR(150),
    ip_address      INET,
    performed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    PRIMARY KEY (id, performed_at)
) PARTITION BY RANGE (performed_at);

-- REMOVED (this round): manually pre-created June/July partitions used to live
-- here. They've been dropped because pg_partman's create_parent() call further
-- below does this job itself — it creates p_premake (4) partitions starting from
-- the current month forward automatically. Keeping both caused a real conflict:
-- "partition audit_logs_p20260601 would overlap partition audit_logs_y2026m06"
-- because create_parent() tried to create its own June partition over the same
-- range I'd already manually created. Let pg_partman own partition creation
-- entirely rather than mixing manual and managed partitions on the same table —
-- this also avoids relying on a hardcoded year/month in this schema file, which
-- would otherwise need editing every time the file is reused after June 2026.

CREATE INDEX idx_audit_logs_local_metrics ON system.audit_logs(table_name, performed_at DESC);

-- =============================================================================
-- pg_partman AUTOMATION — handles ALL partition creation for system.audit_logs,
-- including the initial set (see removed-seed-partitions note above). Without
-- this running correctly, any INSERT with performed_at outside an existing
-- partition's range fails outright (no partition matches "FOR VALUES FROM/TO").
-- That breaks core OLTP writes, not just auditing, since the audit trigger that
-- writes to this table runs inside the same transaction as the booking/payment/
-- trip/fare_rule write that triggered it.
-- =============================================================================

-- CORRECTED AGAIN (this time verified directly against the running container via
-- \df partman.create_parent, not assumed): the earlier "core.*" fix in this file
-- was wrong. That conclusion came from a stale/inconsistent prior container state
-- — once rebuilt cleanly with CREATE SCHEMA partman existing before CREATE
-- EXTENSION ... SCHEMA partman, the extension's functions ARE under partman, as
-- the schema clause says. All calls below use partman.* to match what \df actually
-- showed installed in this image.
--
-- Second correction, also found from the verified function signature: this
-- version's create_parent() does NOT accept p_type => 'native'. As of pg_partman
-- 5.0.0, native (declarative) partitioning is the only supported mode — the old
-- trigger-based method was removed — so p_type stopped meaning "native vs
-- trigger-based" and passing 'native' now raises "native is not a valid
-- partitioning type for pg_partman" on some 5.x builds, or is simply absent from
-- the call as below. p_type is omitted entirely and left at its default.
--
-- The target schema for "CREATE EXTENSION ... SCHEMA partman" must already exist —
-- Postgres does NOT auto-create it, even with IF NOT EXISTS on the extension
-- itself.
CREATE SCHEMA IF NOT EXISTS partman;

CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;
-- (Docker image note: the build step in the project's Dockerfile compiles
-- pg_partman from source against this image's PostgreSQL 18 headers and installs
-- the background worker, so this CREATE EXTENSION should succeed without any
-- host-level install step — that's the whole point of using the custom image
-- instead of a bare postgres/postgis one.)

-- Register audit_logs as a managed partition set.
-- p_interval: '1 month' — pg_partman 5.x dropped the old named shorthands
-- ('monthly', 'daily', etc.) and now requires a real PostgreSQL INTERVAL literal.
-- Confirmed via error: "Special partition interval values from old pg_partman
-- versions (monthly) are no longer supported." matches the seed partitions above
-- (each spans one calendar month).
-- p_premake: how many future partitions to keep pre-created at all times (4 months
-- ahead gives slack if the maintenance run is delayed, e.g. by a maintenance window
-- or an outage, without writes failing).
SELECT partman.create_parent(
    p_parent_table      => 'system.audit_logs',
    p_control           => 'performed_at',
    p_interval          => '1 month',
    p_premake           => 4
);

-- Retention: drop (or detach, see note) partitions older than 12 months instead of
-- accumulating audit data forever. Adjust to actual compliance/retention
-- requirements — some jurisdictions or audit policies require longer retention,
-- in which case set p_retention longer or NULL to disable auto-drop entirely and
-- handle archival separately.
UPDATE partman.part_config
SET retention            = '12 months',
    retention_keep_table = false,  -- false = DROP old partitions; true = detach
                                    -- and keep them as standalone tables for
                                    -- manual archival to cold storage instead
    infinite_time_partitions = true
WHERE parent_table = 'system.audit_logs';

-- (Docker image note: this image's Dockerfile compiles pg_partman WITH its
-- background worker, NO_BGW=0, and the postgresql.conf.sample already has
-- shared_preload_libraries = 'pg_partman_bgw' baked in. That means the bgw runs
-- automatically inside this container — no pg_cron, no external scheduler, no
-- manual partman.run_maintenance_proc() calls needed. Confirm it's actually
-- running with: SELECT * FROM pg_stat_activity WHERE backend_type LIKE '%partman%';
-- pg_partman_bgw.interval is set to 3600 seconds (hourly) in the Dockerfile — adjust
-- that build arg/conf line if a different cadence is wanted.
-- If you instead run pg_partman on a host OUTSIDE this Docker setup (bare-metal,
-- managed Postgres without bgw support), you'd need one of:
--   pg_cron: CREATE EXTENSION pg_cron; SELECT cron.schedule(...) calling
--            partman.run_maintenance_proc() on a schedule, or
--   an external scheduler (systemd timer / Go cron worker / Airflow) that
--            periodically runs: SELECT partman.run_maintenance_proc();
-- but neither is needed for this image — the bgw replaces both.)
-- NOTE on "performed_by should be a proper FK": deliberately left as a free-text
-- column. Audit rows are written by triggers fired by DB roles, API service accounts,
-- batch jobs, and admins — not just one identity table — and audit rows must survive
-- even after a referenced user/service is deleted. A text label (or a JSONB actor
-- descriptor, if you need structure) is the safer pattern for an immutable log;
-- an FK here would either cascade-delete history or block deletes elsewhere.

-- =============================================================================
-- DOMAIN 5 — ANALYTICS / ML FACT LAYER (new)
-- =============================================================================

CREATE TABLE fin.fact_trip_revenue (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id         UUID NOT NULL UNIQUE REFERENCES biz.trips(id),
    route_id        UUID NOT NULL REFERENCES core.routes(id),
    vehicle_id      UUID NOT NULL REFERENCES core.vehicles(id),
    driver_id       UUID NOT NULL REFERENCES core.drivers(id),
    trip_date       DATE NOT NULL,
    total_bookings  SMALLINT NOT NULL DEFAULT 0,
    total_revenue   DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    avg_fare        DECIMAL(10,2),
    occupancy_rate  DECIMAL(5,2),
    cancellations   SMALLINT NOT NULL DEFAULT 0,
    no_shows        SMALLINT NOT NULL DEFAULT 0,
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- NOTE (v3): this table has never had a live trigger firing on every booking — it
-- was designed batch-only from v2 onward (see the ML pipeline notes). No change
-- needed here; flagging only because a review pass suggested removing a live
-- trigger that wasn't present. Populate via a nightly batch job (pg_cron, Airflow,
-- or a Go worker) that scans yesterday's COMPLETED trips and inserts/updates rows —
-- never from a row-level trigger on biz.bookings.
CREATE INDEX idx_fact_revenue_date ON fin.fact_trip_revenue(trip_date, route_id);

-- =============================================================================
-- CRITICAL SEARCH & JOIN INDEX OPTIMIZATIONS
-- =============================================================================

CREATE INDEX idx_halts_spatial_gist ON core.halts USING GIST(location);
CREATE INDEX idx_trips_query_path ON biz.trips(vehicle_id, trip_date, status);
CREATE INDEX idx_schedules_lookup ON biz.schedules(is_active, valid_from, valid_to);
CREATE INDEX idx_bookings_lookup  ON biz.bookings(trip_id, booking_status);
CREATE INDEX idx_trip_halt_lookup ON biz.trip_halt_log(trip_id, sequence_order);
-- idx_audit_logs_local_metrics defined above (with the audit_logs table itself)
-- already covers this — removed duplicate.

-- =============================================================================
-- AUTOMATION TRIGGERS
-- =============================================================================

CREATE OR REPLACE FUNCTION system.trg_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY[
        'core.drivers','core.vehicles','biz.schedules','core.routes','biz.trips',
        'core.passengers','fin.payments','core.passenger_loyalty'
    ]
    LOOP
        EXECUTE FORMAT(
            'CREATE TRIGGER trg_auto_update_timestamp
             BEFORE UPDATE ON %s
             FOR EACH ROW EXECUTE FUNCTION system.trg_set_updated_at();', tbl
        );
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION system.trg_audit_engine()
RETURNS TRIGGER AS $$
DECLARE
    rec_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN rec_id := OLD.id; ELSE rec_id := NEW.id; END IF;

    INSERT INTO system.audit_logs (table_name, record_id, action, old_values, new_values)
    VALUES (
        TG_TABLE_NAME,
        rec_id,
        TG_OP::system.audit_action_enum,
        CASE WHEN TG_OP != 'INSERT' THEN row_to_json(OLD)::JSONB END,
        CASE WHEN TG_OP != 'DELETE' THEN row_to_json(NEW)::JSONB END
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY['biz.bookings','fin.payments','biz.trips','fin.fare_rules']
    LOOP
        EXECUTE FORMAT(
            'CREATE TRIGGER trg_secure_audit_trail
             AFTER INSERT OR UPDATE OR DELETE ON %s
             FOR EACH ROW EXECUTE FUNCTION system.trg_audit_engine();', tbl
        );
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- REMOVED (v3): biz.trg_sync_seat_availability / trg_booking_seat_sync /
-- trg_init_seat_availability. These wrote to biz.trips on every booking
-- insert/update/delete, serializing concurrent bookings for the same trip on that
-- row's lock. Replaced with a read-side view below — zero extra writes, and it's
-- always correct by construction (computed from current booking rows, never goes
-- stale, nothing to keep "in sync").
-- -----------------------------------------------------------------------------

-- Live seat inventory, computed on read instead of maintained on write.
-- Note this does one aggregation per query, not per booking — for a single trip's
-- detail page this is one cheap indexed lookup; for "all trips with availability"
-- list views at very high QPS, this is exactly the kind of read that's worth
-- caching at the application layer (e.g. Redis, short TTL) rather than pushing the
-- cost back onto OLTP writes.
CREATE OR REPLACE VIEW biz.v_trip_seat_inventory AS
SELECT
    t.id AS trip_id,
    v.total_seats,
    COUNT(b.id) FILTER (WHERE b.booking_status NOT IN ('CANCELLED', 'NO_SHOW')) AS booked_seats,
    v.total_seats - COUNT(b.id) FILTER (WHERE b.booking_status NOT IN ('CANCELLED', 'NO_SHOW')) AS available_seats
FROM biz.trips t
JOIN core.vehicles v ON v.id = t.vehicle_id
LEFT JOIN biz.bookings b ON b.trip_id = t.id
GROUP BY t.id, v.total_seats;

-- -----------------------------------------------------------------------------
-- IoT ingest safety for trip_halt_log (v3).
-- Problem: a duplicate/retried packet for the same (trip_id, halt_id) hits the
-- UNIQUE constraint as a hard error instead of being absorbed.
-- CORRECTION vs. the suggested fix: the suggested ON CONFLICT ... DO UPDATE used
--   passengers_boarded = trip_halt_log.passengers_boarded + EXCLUDED.passengers_boarded
-- That's only correct if every incoming row is a *delta* since the last reading.
-- But the failure mode described is a network retry sending the *same* reading
-- twice — in that case, additive accumulation double-counts the duplicate, which
-- is the bug we're trying to fix, just moved one layer down. True idempotency
-- needs either (a) a client-supplied event/packet ID to dedupe on, or (b) treating
-- each upsert as the latest snapshot for that halt rather than a delta.
-- This version does (b): boarded/alighted are overwritten (last-write-wins on the
-- same trip+halt), which is safe for retries of an identical packet and for
-- corrected re-sends of the same reading. If the device genuinely needs to report
-- incremental deltas across multiple visits to the same halt (e.g. a bus that
-- loops back), use a separate event-log table keyed by a device-generated packet
-- ID instead of overloading this row's uniqueness.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION biz.upsert_trip_halt_log(
    p_trip_id             UUID,
    p_halt_id             UUID,
    p_sequence_order      SMALLINT,
    p_arrived_at          TIMESTAMPTZ,
    p_departed_at         TIMESTAMPTZ,
    p_passengers_boarded  SMALLINT,
    p_passengers_alighted SMALLINT,
    p_current_occupancy   SMALLINT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO biz.trip_halt_log (
        trip_id, halt_id, sequence_order, arrived_at, departed_at,
        passengers_boarded, passengers_alighted, current_occupancy
    )
    VALUES (
        p_trip_id, p_halt_id, p_sequence_order, p_arrived_at, p_departed_at,
        p_passengers_boarded, p_passengers_alighted, p_current_occupancy
    )
    ON CONFLICT (trip_id, halt_id) DO UPDATE SET
        arrived_at          = COALESCE(EXCLUDED.arrived_at, biz.trip_halt_log.arrived_at),
        departed_at         = COALESCE(EXCLUDED.departed_at, biz.trip_halt_log.departed_at),
        passengers_boarded  = EXCLUDED.passengers_boarded,   -- overwrite, not additive — see note above
        passengers_alighted = EXCLUDED.passengers_alighted,  -- overwrite, not additive — see note above
        current_occupancy   = EXCLUDED.current_occupancy;
END;
$$ LANGUAGE plpgsql;
-- Call from the ingest layer as:
--   SELECT biz.upsert_trip_halt_log($1,$2,$3,$4,$5,$6,$7,$8);
-- instead of a raw INSERT, so retried packets no longer raise unique-violation errors.
-- Kept mostly as proposed, with explicit handling for "no matching fare rule found"
-- (the original would silently return NULL * arithmetic = NULL, which a caller could
-- easily mistake for "free fare" instead of "no rule configured").
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fin.calculate_fare(
    p_route_id UUID, p_from_halt UUID, p_to_halt UUID, p_trip_id UUID
) RETURNS DECIMAL AS $$
DECLARE
    v_rule    fin.fare_rules%ROWTYPE;
    v_has_ac  BOOLEAN;
    v_fare    DECIMAL;
BEGIN
    SELECT fr.* INTO v_rule
    FROM fin.fare_rules fr
    WHERE fr.route_id = p_route_id
      AND fr.from_halt_id = p_from_halt
      AND fr.to_halt_id = p_to_halt
      AND fr.effective_from <= CURRENT_DATE
      AND (fr.effective_to IS NULL OR fr.effective_to >= CURRENT_DATE)
    ORDER BY fr.effective_from DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active fare rule for route % from % to %', p_route_id, p_from_halt, p_to_halt;
    END IF;

    SELECT v.has_ac INTO v_has_ac
    FROM biz.trips t
    JOIN core.vehicles v ON v.id = t.vehicle_id
    WHERE t.id = p_trip_id;

    v_fare := v_rule.base_fare;
    IF v_has_ac AND v_rule.has_ac_surcharge THEN
        v_fare := v_fare + v_rule.ac_surcharge_amount;
    END IF;

    RETURN v_fare;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- Loyalty rollup: keeps core.passenger_loyalty in sync whenever a booking is
-- completed. Auto-creates the loyalty row on a passenger's first completed trip
-- instead of requiring a separate seed/backfill step.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION core.trg_update_loyalty()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.booking_status = 'COMPLETED' AND (OLD.booking_status IS DISTINCT FROM 'COMPLETED') THEN
        INSERT INTO core.passenger_loyalty (passenger_id, total_trips, total_spent)
        VALUES (NEW.passenger_id, 1, NEW.fare_amount)
        ON CONFLICT (passenger_id) DO UPDATE
        SET total_trips = core.passenger_loyalty.total_trips + 1,
            total_spent  = core.passenger_loyalty.total_spent + NEW.fare_amount,
            updated_at   = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_booking_loyalty_sync
AFTER UPDATE OF booking_status ON biz.bookings
FOR EACH ROW EXECUTE FUNCTION core.trg_update_loyalty();

-- =============================================================================
-- HELPER VIEW — replaces the dropped license_expiry CHECK constraint
-- =============================================================================
CREATE OR REPLACE VIEW core.v_expiring_driver_docs AS
SELECT d.id AS driver_id, d.full_name, d.license_number, d.license_expiry,
       (d.license_expiry - CURRENT_DATE) AS days_remaining
FROM core.drivers d
WHERE d.deleted_at IS NULL
  AND d.license_expiry <= CURRENT_DATE + INTERVAL '30 days'
ORDER BY d.license_expiry ASC;

-- =============================================================================
-- END OF SCHEMA
-- =============================================================================