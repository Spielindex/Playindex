-- =============================================================================
-- Playindex · Venue-Layer
-- Clubs, Plaetze, Oeffnungszeiten, Sperrzeiten, Preise
-- =============================================================================
-- Multi-Tenant ab Tag 1: Sportcenter Hahn ist Club #1, aber das Modell traegt
-- weitere Clubs ohne Migration. Playindex wird damit zur Plattform, nicht zur
-- Einzelplatz-Loesung.
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Clubs
-- -----------------------------------------------------------------------------
create table if not exists booking.clubs (
  id                          uuid primary key default gen_random_uuid(),
  slug                        text        not null unique,
  name                        text        not null,
  timezone                    text        not null default 'Europe/Berlin',

  street                      text,
  postal_code                 text,
  city                        text,
  country                     char(2)     not null default 'DE',
  contact_email               text,
  contact_phone               text,
  website                     text,

  currency                    char(3)     not null default 'EUR',

  -- Buchungsregeln (pro Club konfigurierbar, kein Hardcoding im Frontend)
  slot_minutes                smallint    not null default 30 check (slot_minutes in (15, 30, 60)),
  min_duration_minutes        smallint    not null default 60,
  max_duration_minutes        smallint    not null default 180,
  max_advance_days            smallint    not null default 14,
  cancellation_deadline_hours smallint    not null default 24,
  max_open_bookings_per_user  smallint    not null default 4,

  is_active                   boolean     not null default true,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),

  constraint clubs_duration_sane check (max_duration_minutes >= min_duration_minutes)
);

comment on column booking.clubs.timezone is
  'Alle Zeiten werden als timestamptz (UTC) gespeichert. Oeffnungszeiten/Preise sind lokale Wandzeiten und werden ueber diese TZ aufgeloest -> Sommer-/Winterzeit ist automatisch korrekt.';

drop trigger if exists trg_clubs_touch on booking.clubs;
create trigger trg_clubs_touch before update on booking.clubs
  for each row execute function booking.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Plaetze
-- -----------------------------------------------------------------------------
create table if not exists booking.courts (
  id             uuid primary key default gen_random_uuid(),
  club_id        uuid           not null references booking.clubs(id) on delete cascade,
  slug           text           not null,
  name           text           not null,
  sport          booking.sport  not null,
  surface        text,                                   -- 'sand', 'teppich', 'asche', 'hallenboden'
  is_indoor      boolean        not null default false,
  has_floodlight boolean        not null default true,
  max_players    smallint       not null default 4 check (max_players between 1 and 8),
  sort_order     smallint       not null default 0,
  is_active      boolean        not null default true,
  created_at     timestamptz    not null default now(),
  updated_at     timestamptz    not null default now(),

  unique (club_id, slug)
);

create index if not exists courts_club_sport_idx
  on booking.courts (club_id, sport, sort_order) where is_active;

drop trigger if exists trg_courts_touch on booking.courts;
create trigger trg_courts_touch before update on booking.courts
  for each row execute function booking.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Oeffnungszeiten
-- -----------------------------------------------------------------------------
-- court_id NULL = gilt fuer alle Plaetze des Clubs.
-- Eine platz-spezifische Zeile gewinnt gegen die Club-Zeile.
-- valid_from/valid_to erlauben Sommer-/Winter-Saisonzeiten ohne Datenverlust.
create table if not exists booking.opening_hours (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid     not null references booking.clubs(id)  on delete cascade,
  court_id   uuid              references booking.courts(id) on delete cascade,
  weekday    smallint not null check (weekday between 0 and 6),  -- 0 = Sonntag (extract(dow))
  opens_at   time     not null,
  closes_at  time     not null,                                   -- '24:00' ist zulaessig
  valid_from date     not null default '-infinity',
  valid_to   date     not null default 'infinity',
  created_at timestamptz not null default now(),

  constraint opening_hours_window check (closes_at > opens_at),
  constraint opening_hours_validity check (valid_to >= valid_from)
);

create index if not exists opening_hours_lookup_idx
  on booking.opening_hours (club_id, weekday, court_id);

-- -----------------------------------------------------------------------------
-- Sperrzeiten (Feiertage, Betriebsferien, Turniertage)
-- -----------------------------------------------------------------------------
-- Clubweite Schliessungen. Einzelne Platzsperrungen laufen als Buchung
-- mit type = 'maintenance' -> so gibt es genau EINE Quelle fuer Platzbelegung.
create table if not exists booking.closures (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid        not null references booking.clubs(id)  on delete cascade,
  court_id   uuid                 references booking.courts(id) on delete cascade,
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  reason     text,
  created_at timestamptz not null default now(),

  constraint closures_window check (ends_at > starts_at)
);

create index if not exists closures_lookup_idx
  on booking.closures (club_id, starts_at, ends_at);

-- -----------------------------------------------------------------------------
-- Preisregeln
-- -----------------------------------------------------------------------------
-- Regel-Aufloesung (spezifisch schlaegt allgemein):
--   priority DESC, court_id NOT NULL, sport NOT NULL, weekday NOT NULL
-- Preise werden je 15-Minuten-Segment aufgeloest, damit Buchungen ueber eine
-- Tarifgrenze hinweg (z.B. 18:00-19:30) exakt abgerechnet werden.
create table if not exists booking.pricing_rules (
  id                          uuid primary key default gen_random_uuid(),
  club_id                     uuid          not null references booking.clubs(id)  on delete cascade,
  court_id                    uuid                   references booking.courts(id) on delete cascade,
  sport                       booking.sport,
  weekday                     smallint check (weekday between 0 and 6),
  starts_at                   time          not null default '00:00',
  ends_at                     time          not null default '24:00',
  price_per_hour_cents        integer       not null check (price_per_hour_cents >= 0),
  member_price_per_hour_cents integer                check (member_price_per_hour_cents >= 0),
  valid_from                  date          not null default '-infinity',
  valid_to                    date          not null default 'infinity',
  priority                    smallint      not null default 0,
  label                       text,
  created_at                  timestamptz   not null default now(),

  constraint pricing_window check (ends_at > starts_at)
);

create index if not exists pricing_rules_lookup_idx
  on booking.pricing_rules (club_id, weekday, priority desc);
