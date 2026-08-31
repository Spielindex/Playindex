-- =============================================================================
-- Playindex · Geschaeftslogik in der Datenbank
-- =============================================================================
-- Warum Trigger statt Anwendungscode?
-- Playindex bekommt mehrere Schreib-Clients: SvelteKit-Frontend, Club-Admin,
-- Eversports-Import, spaeter PadelIndex-Sync und Zahlungs-Webhooks. Regeln wie
-- "nicht in der Vergangenheit", "nur innerhalb der Oeffnungszeiten",
-- "Stornofrist" gehoeren deshalb an EINE Stelle - die Datenbank.
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Preisberechnung
-- -----------------------------------------------------------------------------
-- Loest den Preis je 15-Minuten-Segment auf. Eine Buchung 18:00-19:30, bei der
-- ab 19:00 der Abendtarif gilt, wird dadurch exakt korrekt berechnet.
create or replace function booking.calculate_price(
  p_court_id  uuid,
  p_starts_at timestamptz,
  p_ends_at   timestamptz,
  p_user_id   uuid default null
) returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_club_id   uuid;
  v_sport     booking.sport;
  v_tz        text;
  v_is_member boolean := false;
  v_seg       timestamptz;
  v_local     timestamp;
  v_rate      integer;
  v_total     numeric := 0;
begin
  select c.club_id, c.sport, cl.timezone
    into v_club_id, v_sport, v_tz
  from booking.courts c
  join booking.clubs  cl on cl.id = c.club_id
  where c.id = p_court_id;

  if v_club_id is null then
    raise exception 'Platz % existiert nicht', p_court_id using errcode = 'no_data_found';
  end if;

  if p_user_id is not null then
    select exists (
      select 1 from booking.club_members m
      where m.club_id = v_club_id and m.user_id = p_user_id
        and m.tier in ('member','subscriber') and not m.is_blocked
    ) into v_is_member;
  end if;

  for v_seg in
    select gs from pg_catalog.generate_series(
      p_starts_at, p_ends_at - interval '15 minutes', interval '15 minutes'
    ) gs
  loop
    v_local := v_seg at time zone v_tz;

    select case
             when v_is_member then coalesce(r.member_price_per_hour_cents, r.price_per_hour_cents)
             else r.price_per_hour_cents
           end
      into v_rate
    from booking.pricing_rules r
    where r.club_id = v_club_id
      and (r.court_id is null or r.court_id = p_court_id)
      and (r.sport    is null or r.sport    = v_sport)
      and (r.weekday  is null or r.weekday  = extract(dow from v_local)::smallint)
      and v_local::time >= r.starts_at
      and v_local::time <  r.ends_at
      and v_local::date between r.valid_from and r.valid_to
    order by r.priority desc,
             (r.court_id is not null) desc,
             (r.sport    is not null) desc,
             (r.weekday  is not null) desc
    limit 1;

    v_total := v_total + coalesce(v_rate, 0) / 4.0;   -- 15 min = 1/4 Stunde
  end loop;

  return round(v_total)::integer;
end $$;

grant execute on function booking.calculate_price(uuid, timestamptz, timestamptz, uuid)
  to anon, authenticated;

-- -----------------------------------------------------------------------------
-- Validierung jeder Buchung
-- -----------------------------------------------------------------------------
create or replace function booking.validate_booking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club        booking.clubs%rowtype;
  v_court       booking.courts%rowtype;
  v_privileged  boolean;
  v_duration    integer;
  v_local_start timestamp;
  v_local_end   timestamp;
  v_end_time    time;
  v_has_hours   boolean;
  v_open_count  integer;
begin
  select * into v_court from booking.courts where id = new.court_id;
  if not found then
    raise exception 'Platz existiert nicht' using errcode = 'no_data_found';
  end if;

  new.club_id := v_court.club_id;   -- club_id ist immer vom Platz abgeleitet

  select * into v_club from booking.clubs where id = new.club_id;

  -- auth.uid() IS NULL = Service-Role/Server-Kontext (Import, Cron, Webhook).
  v_privileged := (select auth.uid()) is null or booking.is_club_staff(new.club_id);

  if tg_op = 'INSERT' and new.type = 'player' and new.booked_by is null then
    raise exception 'Spielerbuchungen brauchen einen Besitzer' using errcode = '23502';
  end if;

  if not v_club.is_active then
    raise exception 'Club ist derzeit nicht buchbar' using errcode = '42501';
  end if;
  if not v_court.is_active and new.type = 'player' then
    raise exception 'Platz % ist derzeit nicht buchbar', v_court.name using errcode = '42501';
  end if;

  -- Zeitpruefungen nur bei Neuanlage oder tatsaechlicher Zeit-/Platzaenderung.
  if tg_op = 'INSERT'
     or new.starts_at is distinct from old.starts_at
     or new.ends_at   is distinct from old.ends_at
     or new.court_id  is distinct from old.court_id
  then
    v_duration := extract(epoch from (new.ends_at - new.starts_at))::integer / 60;

    if v_duration % v_club.slot_minutes <> 0 then
      raise exception 'Dauer muss ein Vielfaches von % Minuten sein', v_club.slot_minutes
        using errcode = '22023';
    end if;

    v_local_start := new.starts_at at time zone v_club.timezone;
    v_local_end   := new.ends_at   at time zone v_club.timezone;

    if (extract(minute from v_local_start)::integer % v_club.slot_minutes) <> 0
       or extract(second from v_local_start) <> 0 then
      raise exception 'Startzeit muss auf dem %-Minuten-Raster liegen', v_club.slot_minutes
        using errcode = '22023';
    end if;

    if new.type = 'player' then
      if v_duration < v_club.min_duration_minutes or v_duration > v_club.max_duration_minutes then
        raise exception 'Spieldauer muss zwischen % und % Minuten liegen',
          v_club.min_duration_minutes, v_club.max_duration_minutes using errcode = '22023';
      end if;

      if not v_privileged then
        if new.starts_at <= now() then
          raise exception 'Buchungen in der Vergangenheit sind nicht moeglich' using errcode = '22023';
        end if;
        if new.starts_at > now() + pg_catalog.make_interval(days => v_club.max_advance_days) then
          raise exception 'Buchbar sind maximal % Tage im Voraus', v_club.max_advance_days
            using errcode = '22023';
        end if;
      end if;
    end if;

    -- Oeffnungszeiten. Buchung bis Mitternacht: 00:00 lokal == 24:00 Schliesszeit.
    v_end_time := v_local_end::time;
    if v_end_time = time '00:00' then
      v_end_time := time '24:00';
    end if;

    select exists (select 1 from booking.opening_hours oh where oh.club_id = new.club_id)
      into v_has_hours;

    if v_has_hours and not v_privileged then
      if not exists (
        select 1
        from booking.opening_hours oh
        where oh.club_id = new.club_id
          and (oh.court_id is null or oh.court_id = new.court_id)
          and oh.weekday = extract(dow from v_local_start)::smallint
          and v_local_start::time >= oh.opens_at
          and v_end_time          <= oh.closes_at
          and v_local_start::date between oh.valid_from and oh.valid_to
      ) then
        raise exception 'Ausserhalb der Oeffnungszeiten' using errcode = '22023';
      end if;
    end if;

    -- Clubweite Schliessungen
    if not v_privileged and exists (
      select 1
      from booking.closures cl
      where cl.club_id = new.club_id
        and (cl.court_id is null or cl.court_id = new.court_id)
        and tstzrange(cl.starts_at, cl.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception 'Der Platz ist in diesem Zeitraum gesperrt' using errcode = '42501';
    end if;
  end if;

  -- Kontingent: wie viele offene Buchungen darf ein Spieler gleichzeitig halten?
  if tg_op = 'INSERT' and new.type = 'player' and not v_privileged then
    select count(*) into v_open_count
    from booking.bookings b
    where b.booked_by = new.booked_by
      and b.club_id   = new.club_id
      and b.status in ('pending','confirmed')
      and b.starts_at > now();

    if v_open_count >= v_club.max_open_bookings_per_user then
      raise exception 'Maximal % offene Buchungen gleichzeitig', v_club.max_open_bookings_per_user
        using errcode = '42501';
    end if;
  end if;

  -- Preis serverseitig setzen: der Client darf den Preis nie bestimmen.
  if new.type = 'player' and (tg_op = 'INSERT' or new.starts_at is distinct from old.starts_at
                              or new.ends_at is distinct from old.ends_at
                              or new.court_id is distinct from old.court_id) then
    new.price_cents := booking.calculate_price(new.court_id, new.starts_at, new.ends_at, new.booked_by);
    new.currency    := v_club.currency;
  end if;

  return new;
end $$;

-- -----------------------------------------------------------------------------
-- Was darf ein Spieler an einer bestehenden Buchung aendern?
-- -----------------------------------------------------------------------------
create or replace function booking.enforce_update_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_club       booking.clubs%rowtype;
  v_privileged boolean;
begin
  select * into v_club from booking.clubs where id = old.club_id;
  v_privileged := (select auth.uid()) is null or booking.is_club_staff(old.club_id);

  if v_privileged then
    if new.status = 'cancelled' and old.status <> 'cancelled' then
      new.cancelled_at := coalesce(new.cancelled_at, now());
      new.cancelled_by := coalesce(new.cancelled_by, (select auth.uid()));
    end if;
    return new;
  end if;

  -- Spieler duerfen nicht umbuchen (sonst waere die Preis-/Verfuegbarkeitslogik
  -- umgehbar) - stornieren und neu buchen.
  if new.court_id    is distinct from old.court_id
     or new.club_id  is distinct from old.club_id
     or new.starts_at is distinct from old.starts_at
     or new.ends_at   is distinct from old.ends_at
     or new.type      is distinct from old.type
     or new.price_cents is distinct from old.price_cents
     or new.booked_by   is distinct from old.booked_by
  then
    raise exception 'Umbuchen ist nicht moeglich - bitte stornieren und neu buchen'
      using errcode = '42501';
  end if;

  if new.status is distinct from old.status then
    if new.status <> 'cancelled' then
      raise exception 'Nur Stornierung ist erlaubt' using errcode = '42501';
    end if;
    if old.status not in ('pending','confirmed') then
      raise exception 'Diese Buchung ist bereits abgeschlossen' using errcode = '42501';
    end if;
    if old.starts_at - now() < pg_catalog.make_interval(hours => v_club.cancellation_deadline_hours) then
      raise exception 'Die Stornofrist von % Stunden ist abgelaufen', v_club.cancellation_deadline_hours
        using errcode = '42501';
    end if;
    new.cancelled_at := now();
    new.cancelled_by := (select auth.uid());
  end if;

  return new;
end $$;

-- -----------------------------------------------------------------------------
-- Ereignis-Log
-- -----------------------------------------------------------------------------
create or replace function booking.log_booking_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into booking.booking_events (booking_id, event, actor_id, payload)
    values (new.id, 'created', (select auth.uid()),
            jsonb_build_object('status', new.status, 'type', new.type, 'price_cents', new.price_cents));
  elsif new.status is distinct from old.status then
    insert into booking.booking_events (booking_id, event, actor_id, payload)
    values (new.id,
            case when new.status = 'cancelled' then 'cancelled' else 'status_changed' end,
            (select auth.uid()),
            jsonb_build_object('from', old.status, 'to', new.status, 'reason', new.cancellation_reason));
  end if;
  return null;
end $$;

-- Storniertes Match verschwindet automatisch aus dem Matchmaking.
create or replace function booking.sync_open_match_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status in ('cancelled','no_show') and old.status is distinct from new.status then
    update booking.open_matches set status = 'cancelled'
    where booking_id = new.id and status <> 'cancelled';
  end if;
  return null;
end $$;

-- Volles Match schliesst sich selbst.
create or replace function booking.sync_open_match_slots()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking_id uuid := coalesce(new.booking_id, old.booking_id);
  v_accepted   integer;
  v_capacity   integer;
begin
  if not exists (select 1 from booking.open_matches where booking_id = v_booking_id) then
    return null;
  end if;

  select count(*) into v_accepted
  from booking.booking_participants p
  where p.booking_id = v_booking_id and p.status = 'accepted';

  select b.player_count into v_capacity
  from booking.bookings b where b.id = v_booking_id;

  -- Explizite Casts: ein CASE aus reinen Literalen liefert text, nicht das Enum.
  update booking.open_matches
  set status = case
                 when status = 'cancelled' then 'cancelled'::booking.open_match_status
                 when v_accepted >= v_capacity then 'full'::booking.open_match_status
                 else 'open'::booking.open_match_status
               end
  where booking_id = v_booking_id;

  return null;
end $$;

-- -----------------------------------------------------------------------------
-- Trigger verdrahten (Namen bestimmen die Reihenfolge: guard vor validate)
-- -----------------------------------------------------------------------------
drop trigger if exists trg_bookings_guard    on booking.bookings;
drop trigger if exists trg_bookings_validate on booking.bookings;
drop trigger if exists trg_bookings_log      on booking.bookings;
drop trigger if exists trg_bookings_match    on booking.bookings;

create trigger trg_bookings_guard
  before update on booking.bookings
  for each row execute function booking.enforce_update_rules();

create trigger trg_bookings_validate
  before insert or update on booking.bookings
  for each row execute function booking.validate_booking();

create trigger trg_bookings_log
  after insert or update on booking.bookings
  for each row execute function booking.log_booking_event();

create trigger trg_bookings_match
  after update on booking.bookings
  for each row execute function booking.sync_open_match_on_cancel();

drop trigger if exists trg_participants_match on booking.booking_participants;
create trigger trg_participants_match
  after insert or update or delete on booking.booking_participants
  for each row execute function booking.sync_open_match_slots();
