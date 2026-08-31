-- =============================================================================
-- Playindex · Matchmaking-Connect & Zahlungen
-- =============================================================================
-- "Als offenes Match einstellen" ist im Datenmodell eine 1:0..1-Erweiterung der
-- Buchung, keine Spalte in `bookings`. Grund:
--   * bookings bleibt schlank und schnell (Grid-Query trifft sie am haeufigsten)
--   * das Index-Oekosystem (padelindex.de / tennisindex.eu) synchronisiert genau
--     eine Tabelle und braucht keinen Zugriff auf Buchungsdetails/Preise
--   * Ein Match kann geschlossen/wieder geoeffnet werden, ohne die Buchung anzufassen
-- =============================================================================

set search_path = public, extensions;

create table if not exists booking.open_matches (
  booking_id      uuid primary key references booking.bookings(id) on delete cascade,
  sport           booking.sport             not null,
  platform        booking.index_platform    not null,  -- Ziel-Portal fuer die Veroeffentlichung
  status          booking.open_match_status not null default 'open',

  players_needed  smallint                  not null default 1 check (players_needed between 1 and 7),
  level_min       numeric(6,1),                        -- Elo-Untergrenze
  level_max       numeric(6,1),                        -- Elo-Obergrenze
  gender_preference text                    not null default 'any'
    check (gender_preference in ('any','men','women','mixed')),
  visibility      text                      not null default 'public'
    check (visibility in ('public','club','friends')),
  description     text,
  is_ranked       boolean                   not null default true,  -- zaehlt fuers Elo?

  -- Sync in Richtung PadelIndex/TennisIndex
  external_match_id text,
  external_url      text,
  published_at      timestamptz,
  synced_at         timestamptz,
  sync_error        text,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint open_match_level_range check (level_max is null or level_min is null or level_max >= level_min)
);

comment on table booking.open_matches is
  'Der "Open Match"-Toggle. Existiert eine Zeile mit status=open, sucht die Buchung Mitspieler ueber das Index-Oekosystem.';

create index if not exists open_matches_discovery_idx
  on booking.open_matches (platform, status, published_at desc) where status = 'open';

drop trigger if exists trg_open_matches_touch on booking.open_matches;
create trigger trg_open_matches_touch before update on booking.open_matches
  for each row execute function booking.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Zahlungen  ·  vorbereitet, noch nicht aktiv
-- -----------------------------------------------------------------------------
-- Eine Zahlung haengt optional am Teilnehmer (participant_id) statt nur an der
-- Buchung. Genau das macht Split-Payments spaeter zu einem Feature-Flag statt
-- zu einer Migration: 1 Buchung -> N Zahlungen, je eine pro Spieler.
create table if not exists booking.payments (
  id                 uuid primary key default gen_random_uuid(),
  booking_id         uuid                   not null references booking.bookings(id) on delete cascade,
  participant_id     uuid                   references booking.booking_participants(id) on delete set null,
  user_id            uuid                   references auth.users(id) on delete set null,

  amount_cents       integer                not null check (amount_cents > 0),
  refunded_cents     integer                not null default 0 check (refunded_cents >= 0),
  currency           char(3)                not null default 'EUR',

  provider           text                   not null default 'stripe',
  provider_intent_id text,
  status             booking.payment_status not null default 'pending',

  created_at         timestamptz            not null default now(),
  paid_at            timestamptz,

  unique (provider, provider_intent_id)
);

create index if not exists payments_booking_idx on booking.payments (booking_id);
create index if not exists payments_user_idx    on booking.payments (user_id, created_at desc);
