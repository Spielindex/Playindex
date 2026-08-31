-- =============================================================================
-- Playindex · Buchungen
-- =============================================================================
-- ZENTRALE ENTSCHEIDUNG: Doppelbuchungen werden von der DATENBANK verhindert,
-- nicht von der Anwendung. Ein EXCLUDE-Constraint ueber (court_id, Zeitraum)
-- macht ueberlappende aktive Buchungen physikalisch unmoeglich - auch bei
-- gleichzeitigen Requests, Race Conditions oder direktem SQL-Zugriff.
-- Das ist der Unterschied zwischen "wir pruefen vorher" und "kann nicht passieren".
--
-- Ausserdem: Wartung, Kurse und Turniere sind Buchungen mit anderem `type`.
-- Damit gibt es genau EINE Tabelle, die Platzbelegung definiert - und der
-- EXCLUDE-Constraint schuetzt sie alle gleichermassen.
-- =============================================================================

set search_path = public, extensions;

create table if not exists booking.bookings (
  id                  uuid primary key default gen_random_uuid(),
  club_id             uuid                   not null references booking.clubs(id)  on delete restrict,
  court_id            uuid                   not null references booking.courts(id) on delete restrict,

  starts_at           timestamptz            not null,
  ends_at             timestamptz            not null,
  time_range          tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,

  type                booking.booking_type   not null default 'player',
  status              booking.booking_status not null default 'confirmed',

  -- ON DELETE SET NULL statt CASCADE: bei DSGVO-Loeschung eines Accounts
  -- bleibt die Buchungshistorie fuer die Club-Buchhaltung anonymisiert erhalten.
  booked_by           uuid                   references auth.users(id) on delete set null,

  player_count        smallint               not null default 4 check (player_count between 1 and 8),
  price_cents         integer                not null default 0 check (price_cents >= 0),
  currency            char(3)                not null default 'EUR',

  title               text,   -- fuer Kurse/Turniere ("Anfaengertraining Padel")
  note                text,

  cancelled_at        timestamptz,
  cancelled_by        uuid                   references auth.users(id) on delete set null,
  cancellation_reason text,

  source              text                   not null default 'web',  -- 'web' | 'admin' | 'import' | 'padelindex'
  created_at          timestamptz            not null default now(),
  updated_at          timestamptz            not null default now(),

  constraint bookings_time_valid check (ends_at > starts_at),

  -- Der Kern: keine zwei aktiven Buchungen auf demselben Platz zur selben Zeit.
  constraint bookings_no_overlap exclude using gist (
    court_id   with =,
    time_range with &&
  ) where (status in ('pending','confirmed'))
);

comment on constraint bookings_no_overlap on booking.bookings is
  'Garantiert Ueberlappungsfreiheit pro Platz auf DB-Ebene. Verletzung -> SQLSTATE 23P01 (exclusion_violation), im Frontend als "Slot gerade vergeben" behandeln.';

create index if not exists bookings_court_time_idx on booking.bookings (court_id, starts_at);
create index if not exists bookings_club_time_idx  on booking.bookings (club_id, starts_at desc);
create index if not exists bookings_user_time_idx  on booking.bookings (booked_by, starts_at desc);
create index if not exists bookings_active_idx     on booking.bookings (club_id, starts_at)
  where status in ('pending','confirmed');

drop trigger if exists trg_bookings_touch on booking.bookings;
create trigger trg_bookings_touch before update on booking.bookings
  for each row execute function booking.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Teilnehmer  ·  Basis fuer Matchmaking UND Split-Payments
-- -----------------------------------------------------------------------------
-- Diese Tabelle ist der Grund, warum Split-Payments spaeter ohne Schema-Bruch
-- nachruestbar sind: die Kostenaufteilung haengt bereits jetzt am Teilnehmer,
-- nicht an der Buchung. Heute zahlt der Host alles (share_cents = Gesamtpreis
-- beim Host), morgen wird derselbe Datensatz auf 4 Spieler aufgeteilt.
create table if not exists booking.booking_participants (
  id             uuid primary key default gen_random_uuid(),
  booking_id     uuid                       not null references booking.bookings(id) on delete cascade,
  user_id        uuid                       references auth.users(id) on delete set null,
  guest_name     text,
  guest_email    text,
  is_host        boolean                    not null default false,
  status         booking.participant_status not null default 'invited',

  -- Split-Payment-Felder (heute optional, morgen aktiv)
  share_cents    integer                    not null default 0 check (share_cents >= 0),
  paid_cents     integer                    not null default 0 check (paid_cents >= 0),
  payment_status booking.payment_status     not null default 'unpaid',

  joined_at      timestamptz                not null default now(),

  constraint participant_identified check (user_id is not null or guest_name is not null)
);

-- Ein Nutzer kann pro Buchung nur einmal Teilnehmer sein.
create unique index if not exists booking_participants_unique_user_idx
  on booking.booking_participants (booking_id, user_id) where user_id is not null;

-- Genau ein Host pro Buchung.
create unique index if not exists booking_participants_single_host_idx
  on booking.booking_participants (booking_id) where is_host;

create index if not exists booking_participants_user_idx
  on booking.booking_participants (user_id) where user_id is not null;

-- -----------------------------------------------------------------------------
-- Ereignis-Log  ·  Stornoquoten, No-Shows, Support-Rueckfragen
-- -----------------------------------------------------------------------------
create table if not exists booking.booking_events (
  id         bigint generated always as identity primary key,
  booking_id uuid        not null references booking.bookings(id) on delete cascade,
  event      text        not null,   -- 'created' | 'cancelled' | 'status_changed' | ...
  actor_id   uuid                 references auth.users(id) on delete set null,
  payload    jsonb       not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists booking_events_booking_idx
  on booking.booking_events (booking_id, created_at desc);
