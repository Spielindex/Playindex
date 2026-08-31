-- =============================================================================
-- Playindex · Lese-API (Views & RPCs)
-- =============================================================================
-- DATENSCHUTZ-ENTSCHEIDUNG
-- Das Buchungs-Grid muss OHNE Login funktionieren (3-Klick-Ziel), darf aber
-- niemals verraten, WER gebucht hat. Loesung: `booking.bookings` ist fuer anon
-- komplett gesperrt; oeffentlich sichtbar ist ausschliesslich die View
-- `v_court_availability` - sie zeigt nur "belegt von wann bis wann".
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Oeffentliche Verfuegbarkeit (ohne Identitaeten)
-- -----------------------------------------------------------------------------
create or replace view booking.v_court_availability as
select
  b.id                                             as booking_id,
  b.club_id,
  b.court_id,
  b.starts_at,
  b.ends_at,
  b.status,
  b.type,
  (om.booking_id is not null and om.status = 'open') as is_open_match,
  om.players_needed,
  om.level_min,
  om.level_max
from booking.bookings b
left join booking.open_matches om on om.booking_id = b.id
where b.status in ('pending','confirmed');

comment on view booking.v_court_availability is
  'Oeffentliche Belegung. Bewusst ohne booked_by/note/price - anon darf sehen DASS belegt ist, nicht WER bucht.';

-- -----------------------------------------------------------------------------
-- Offene Matches (Discovery-Feed fuer PadelIndex / TennisIndex)
-- -----------------------------------------------------------------------------
create or replace view booking.v_open_matches as
select
  om.booking_id,
  om.sport,
  om.platform,
  om.players_needed,
  om.level_min,
  om.level_max,
  om.gender_preference,
  om.description,
  om.is_ranked,
  om.external_match_id,
  om.external_url,
  b.starts_at,
  b.ends_at,
  b.player_count,
  c.name                as court_name,
  c.is_indoor,
  cl.id                 as club_id,
  cl.slug               as club_slug,
  cl.name               as club_name,
  cl.city,
  (select count(*) from booking.booking_participants p
    where p.booking_id = om.booking_id and p.status = 'accepted')::smallint as players_joined
from booking.open_matches om
join booking.bookings b on b.id = om.booking_id
join booking.courts   c on c.id = b.court_id
join booking.clubs    cl on cl.id = b.club_id
where om.status = 'open'
  and om.visibility = 'public'
  and b.status in ('pending','confirmed')
  and b.starts_at > now();

comment on view booking.v_open_matches is
  'Feed fuer padelindex.de / tennisindex.eu. Enthaelt keine Spielernamen - die kommen aus dem Index-Profil des jeweiligen Portals.';

-- -----------------------------------------------------------------------------
-- RPC: kompletter Tagesplan fuer das Buchungs-Grid  (EIN Roundtrip)
-- -----------------------------------------------------------------------------
create or replace function booking.get_day_schedule(
  p_club_slug text,
  p_date      date,
  p_sport     booking.sport default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club   booking.clubs%rowtype;
  v_from   timestamptz;
  v_to     timestamptz;
  v_result jsonb;
begin
  select * into v_club from booking.clubs where slug = p_club_slug and is_active;
  if not found then
    raise exception 'Club % nicht gefunden', p_club_slug using errcode = 'no_data_found';
  end if;

  v_from := (p_date::timestamp)       at time zone v_club.timezone;
  v_to   := ((p_date + 1)::timestamp) at time zone v_club.timezone;

  select jsonb_build_object(
    'club', jsonb_build_object(
      'id',                   v_club.id,
      'slug',                 v_club.slug,
      'name',                 v_club.name,
      'timezone',             v_club.timezone,
      'currency',             v_club.currency,
      'slot_minutes',         v_club.slot_minutes,
      'min_duration_minutes', v_club.min_duration_minutes,
      'max_duration_minutes', v_club.max_duration_minutes,
      'max_advance_days',     v_club.max_advance_days,
      'cancellation_deadline_hours', v_club.cancellation_deadline_hours
    ),
    'date', p_date,
    'closures', coalesce((
      select jsonb_agg(jsonb_build_object(
               'court_id', cl.court_id, 'starts_at', cl.starts_at,
               'ends_at', cl.ends_at, 'reason', cl.reason))
      from booking.closures cl
      where cl.club_id = v_club.id
        and tstzrange(cl.starts_at, cl.ends_at, '[)') && tstzrange(v_from, v_to, '[)')
    ), '[]'::jsonb),
    'courts', coalesce(jsonb_agg(x.court order by x.sort_order, x.name), '[]'::jsonb)
  )
  into v_result
  from (
    select
      c.sort_order,
      c.name,
      jsonb_build_object(
        'id',          c.id,
        'slug',        c.slug,
        'name',        c.name,
        'sport',       c.sport,
        'surface',     c.surface,
        'is_indoor',   c.is_indoor,
        'max_players', c.max_players,
        'opens_at',    oh.opens_at,
        'closes_at',   oh.closes_at,
        'bookings',    coalesce(bk.items, '[]'::jsonb)
      ) as court
    from booking.courts c
    left join lateral (
      select oh2.opens_at, oh2.closes_at
      from booking.opening_hours oh2
      where oh2.club_id = c.club_id
        and (oh2.court_id is null or oh2.court_id = c.id)
        and oh2.weekday = extract(dow from p_date)::smallint
        and p_date between oh2.valid_from and oh2.valid_to
      order by (oh2.court_id is not null) desc
      limit 1
    ) oh on true
    left join lateral (
      select jsonb_agg(
               jsonb_build_object(
                 'id',            a.booking_id,
                 'starts_at',     a.starts_at,
                 'ends_at',       a.ends_at,
                 'status',        a.status,
                 'type',          a.type,
                 'is_open_match', a.is_open_match,
                 'players_needed', a.players_needed,
                 'level_min',     a.level_min,
                 'level_max',     a.level_max,
                 'is_mine',       (a.booking_id in (
                                     select b2.id from booking.bookings b2
                                     where b2.booked_by = (select auth.uid())
                                   ))
               ) order by a.starts_at
             ) as items
      from booking.v_court_availability a
      where a.court_id = c.id
        and tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(v_from, v_to, '[)')
    ) bk on true
    where c.club_id = v_club.id
      and c.is_active
      and (p_sport is null or c.sport = p_sport)
  ) x;

  return v_result;
end $$;

comment on function booking.get_day_schedule(text, date, booking.sport) is
  'Ein Aufruf = alles, was das BookingGrid fuer einen Tag braucht: Club-Regeln, Plaetze, Oeffnungszeiten, Belegung, Open Matches, Sperrungen.';

grant execute on function booking.get_day_schedule(text, date, booking.sport) to anon, authenticated;

-- -----------------------------------------------------------------------------
-- RPC: Buchung anlegen  (atomar: Buchung + Host + Teilnehmer + Open Match)
-- -----------------------------------------------------------------------------
-- SECURITY INVOKER: laeuft mit den Rechten des Aufrufers, RLS greift also
-- vollstaendig. Die Funktion ist Bequemlichkeit, kein Sicherheits-Bypass.
create or replace function booking.create_booking(
  p_court_id     uuid,
  p_starts_at    timestamptz,
  p_ends_at      timestamptz,
  p_player_count smallint default null,
  p_note         text     default null,
  p_open_match   jsonb    default null,
  p_participants jsonb    default '[]'::jsonb
) returns booking.bookings
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_court   booking.courts%rowtype;
  v_booking booking.bookings%rowtype;
  v_p       jsonb;
begin
  if v_uid is null then
    raise exception 'Bitte zuerst anmelden' using errcode = '42501';
  end if;

  select * into v_court from booking.courts where id = p_court_id and is_active;
  if not found then
    raise exception 'Platz nicht verfuegbar' using errcode = 'no_data_found';
  end if;

  insert into booking.bookings (club_id, court_id, starts_at, ends_at, type, status, booked_by, player_count, note)
  values (v_court.club_id, p_court_id, p_starts_at, p_ends_at, 'player', 'confirmed', v_uid,
          coalesce(p_player_count, v_court.max_players), p_note)
  returning * into v_booking;

  insert into booking.booking_participants (booking_id, user_id, is_host, status, share_cents)
  values (v_booking.id, v_uid, true, 'accepted', v_booking.price_cents);

  for v_p in select value from jsonb_array_elements(coalesce(p_participants, '[]'::jsonb))
  loop
    insert into booking.booking_participants (booking_id, user_id, guest_name, guest_email, status)
    values (
      v_booking.id,
      nullif(v_p->>'user_id','')::uuid,
      nullif(v_p->>'guest_name',''),
      nullif(v_p->>'guest_email',''),
      'invited'
    )
    on conflict do nothing;
  end loop;

  -- Der "Open Match"-Toggle
  if p_open_match is not null and coalesce((p_open_match->>'enabled')::boolean, true) then
    insert into booking.open_matches (
      booking_id, sport, platform, players_needed,
      level_min, level_max, gender_preference, visibility, description, published_at
    )
    values (
      v_booking.id,
      v_court.sport,
      (case v_court.sport when 'padel' then 'padelindex' else 'tennisindex' end)::booking.index_platform,
      coalesce((p_open_match->>'players_needed')::smallint, (v_booking.player_count - 1)::smallint),
      (p_open_match->>'level_min')::numeric,
      (p_open_match->>'level_max')::numeric,
      coalesce(p_open_match->>'gender_preference', 'any'),
      coalesce(p_open_match->>'visibility', 'public'),
      nullif(p_open_match->>'description',''),
      now()
    );
  end if;

  return v_booking;
end $$;

comment on function booking.create_booking is
  'Ein Roundtrip fuer den kompletten Buchungsvorgang. Bei Slot-Kollision wirft die DB SQLSTATE 23P01 (exclusion_violation).';

revoke all on function booking.create_booking(uuid, timestamptz, timestamptz, smallint, text, jsonb, jsonb) from public, anon;
grant execute on function booking.create_booking(uuid, timestamptz, timestamptz, smallint, text, jsonb, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- RPC: Stornieren
-- -----------------------------------------------------------------------------
create or replace function booking.cancel_booking(p_booking_id uuid, p_reason text default null)
returns booking.bookings
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_booking booking.bookings%rowtype;
begin
  update booking.bookings
  set status = 'cancelled', cancellation_reason = p_reason
  where id = p_booking_id
  returning * into v_booking;

  if not found then
    raise exception 'Buchung nicht gefunden oder keine Berechtigung' using errcode = '42501';
  end if;

  return v_booking;
end $$;

revoke all on function booking.cancel_booking(uuid, text) from public, anon;
grant execute on function booking.cancel_booking(uuid, text) to authenticated;
