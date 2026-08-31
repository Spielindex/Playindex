-- =============================================================================
-- Playindex · Row Level Security
-- =============================================================================
-- Grundhaltung: deny by default. Jede Tabelle hat RLS an, jede Rolle bekommt
-- nur explizit, was sie braucht.
--
--   anon          -> Stammdaten + Verfuegbarkeit (Grid ohne Login) + offene Matches
--   authenticated -> eigene Buchungen, eigene Teilnahmen, eigene Clubdaten
--   staff/admin   -> alles ihres Clubs (ueber booking.is_club_staff())
--   service_role  -> umgeht RLS (Webhooks, Import, SSO-Bridge) - nie im Browser!
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Tabellen-Grants (neue Schemas erben keine Supabase-Defaults)
-- -----------------------------------------------------------------------------
grant select on booking.clubs, booking.courts, booking.opening_hours,
                booking.pricing_rules, booking.closures        to anon, authenticated;

grant select, insert, update on booking.bookings               to authenticated;
grant select, insert, update, delete on booking.booking_participants to authenticated;
grant select, insert, update, delete on booking.open_matches   to authenticated;
grant select                 on booking.payments               to authenticated;
grant select                 on booking.booking_events         to authenticated;
grant select, insert, update on booking.club_members           to authenticated;
grant select                 on booking.club_staff             to authenticated;
grant select, insert, update, delete on booking.club_member_notes to authenticated;

grant select on booking.v_court_availability to anon, authenticated;
grant select on booking.v_open_matches       to anon, authenticated;

grant all on all tables    in schema booking to service_role;
grant all on all sequences in schema booking to service_role;
grant all on all functions in schema booking to service_role;

alter table booking.clubs              enable row level security;
alter table booking.courts             enable row level security;
alter table booking.opening_hours      enable row level security;
alter table booking.closures           enable row level security;
alter table booking.pricing_rules      enable row level security;
alter table booking.club_staff         enable row level security;
alter table booking.club_members       enable row level security;
alter table booking.club_member_notes  enable row level security;
alter table booking.bookings           enable row level security;
alter table booking.booking_participants enable row level security;
alter table booking.booking_events     enable row level security;
alter table booking.open_matches       enable row level security;
alter table booking.payments           enable row level security;

-- -----------------------------------------------------------------------------
-- Stammdaten: oeffentlich lesbar, nur Personal schreibt
-- -----------------------------------------------------------------------------
drop policy if exists clubs_read on booking.clubs;
create policy clubs_read on booking.clubs
  for select to anon, authenticated
  using (is_active or booking.is_club_staff(id));

drop policy if exists clubs_write on booking.clubs;
create policy clubs_write on booking.clubs
  for update to authenticated
  using (booking.has_club_role(id, array['owner','admin']::booking.staff_role[]))
  with check (booking.has_club_role(id, array['owner','admin']::booking.staff_role[]));

drop policy if exists courts_read on booking.courts;
create policy courts_read on booking.courts
  for select to anon, authenticated
  using (is_active or booking.is_club_staff(club_id));

drop policy if exists courts_write on booking.courts;
create policy courts_write on booking.courts
  for all to authenticated
  using (booking.has_club_role(club_id, array['owner','admin']::booking.staff_role[]))
  with check (booking.has_club_role(club_id, array['owner','admin']::booking.staff_role[]));

drop policy if exists opening_hours_read on booking.opening_hours;
create policy opening_hours_read on booking.opening_hours
  for select to anon, authenticated using (true);

drop policy if exists opening_hours_write on booking.opening_hours;
create policy opening_hours_write on booking.opening_hours
  for all to authenticated
  using (booking.is_club_staff(club_id)) with check (booking.is_club_staff(club_id));

drop policy if exists closures_read on booking.closures;
create policy closures_read on booking.closures
  for select to anon, authenticated using (true);

drop policy if exists closures_write on booking.closures;
create policy closures_write on booking.closures
  for all to authenticated
  using (booking.is_club_staff(club_id)) with check (booking.is_club_staff(club_id));

-- Preise sind oeffentlich - der Spieler soll vor dem Login sehen, was es kostet.
drop policy if exists pricing_read on booking.pricing_rules;
create policy pricing_read on booking.pricing_rules
  for select to anon, authenticated using (true);

drop policy if exists pricing_write on booking.pricing_rules;
create policy pricing_write on booking.pricing_rules
  for all to authenticated
  using (booking.has_club_role(club_id, array['owner','admin']::booking.staff_role[]))
  with check (booking.has_club_role(club_id, array['owner','admin']::booking.staff_role[]));

-- -----------------------------------------------------------------------------
-- Club-Team
-- -----------------------------------------------------------------------------
drop policy if exists club_staff_read on booking.club_staff;
create policy club_staff_read on booking.club_staff
  for select to authenticated
  using (user_id = (select auth.uid()) or booking.is_club_staff(club_id));

-- Personal wird ausschliesslich serverseitig (service_role) verwaltet -
-- bewusst keine INSERT/UPDATE-Policy fuer authenticated.

-- -----------------------------------------------------------------------------
-- Club-Mitgliedschaft
-- -----------------------------------------------------------------------------
drop policy if exists club_members_read on booking.club_members;
create policy club_members_read on booking.club_members
  for select to authenticated
  using (user_id = (select auth.uid()) or booking.is_club_staff(club_id));

-- Selbstregistrierung als Gast: Tarif/Guthaben kann sich niemand selbst setzen.
drop policy if exists club_members_self_insert on booking.club_members;
create policy club_members_self_insert on booking.club_members
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and tier = 'guest'
    and credit_cents = 0
    and no_show_count = 0
    and not is_blocked
  );

drop policy if exists club_members_self_update on booking.club_members;
create policy club_members_self_update on booking.club_members
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists club_members_staff on booking.club_members;
create policy club_members_staff on booking.club_members
  for all to authenticated
  using (booking.is_club_staff(club_id)) with check (booking.is_club_staff(club_id));

-- Selbst-Update darf Tarif/Guthaben/Sperre nicht veraendern (RLS kennt keine
-- Spalten-Policies -> Trigger).
create or replace function booking.guard_member_self_update()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or booking.is_club_staff(old.club_id) then
    return new;
  end if;
  if new.tier is distinct from old.tier
     or new.credit_cents  is distinct from old.credit_cents
     or new.no_show_count is distinct from old.no_show_count
     or new.is_blocked    is distinct from old.is_blocked
     or new.member_number is distinct from old.member_number then
    raise exception 'Diese Felder verwaltet nur der Club' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists trg_club_members_guard on booking.club_members;
create trigger trg_club_members_guard before update on booking.club_members
  for each row execute function booking.guard_member_self_update();

drop policy if exists member_notes_staff on booking.club_member_notes;
create policy member_notes_staff on booking.club_member_notes
  for all to authenticated
  using (booking.is_club_staff(club_id)) with check (booking.is_club_staff(club_id));

-- -----------------------------------------------------------------------------
-- Buchungen
-- -----------------------------------------------------------------------------
-- Kein anon-SELECT: die oeffentliche Belegung laeuft ueber v_court_availability.
create or replace function booking.is_booking_member(p_booking_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from booking.bookings b
    where b.id = p_booking_id
      and (
        b.booked_by = (select auth.uid())
        or exists (
          select 1 from booking.booking_participants p
          where p.booking_id = b.id and p.user_id = (select auth.uid())
        )
      )
  );
$$;
grant execute on function booking.is_booking_member(uuid) to authenticated;

drop policy if exists bookings_read_own on booking.bookings;
create policy bookings_read_own on booking.bookings
  for select to authenticated
  using (
    booked_by = (select auth.uid())
    or booking.is_booking_member(id)
    or booking.is_club_staff(club_id)
  );

drop policy if exists bookings_insert_own on booking.bookings;
create policy bookings_insert_own on booking.bookings
  for insert to authenticated
  with check (
    (booked_by = (select auth.uid()) and type = 'player' and status in ('pending','confirmed'))
    or booking.is_club_staff(club_id)
  );

drop policy if exists bookings_update_own on booking.bookings;
create policy bookings_update_own on booking.bookings
  for update to authenticated
  using (booked_by = (select auth.uid()) or booking.is_club_staff(club_id))
  with check (booked_by = (select auth.uid()) or booking.is_club_staff(club_id));

-- Kein DELETE fuer Spieler: Buchungen werden storniert, nicht geloescht.
drop policy if exists bookings_delete_staff on booking.bookings;
create policy bookings_delete_staff on booking.bookings
  for delete to authenticated
  using (booking.has_club_role(club_id, array['owner','admin']::booking.staff_role[]));

-- -----------------------------------------------------------------------------
-- Teilnehmer
-- -----------------------------------------------------------------------------
create or replace function booking.is_booking_host(p_booking_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from booking.bookings b
    where b.id = p_booking_id
      and (b.booked_by = (select auth.uid()) or booking.is_club_staff(b.club_id))
  );
$$;
grant execute on function booking.is_booking_host(uuid) to authenticated;

drop policy if exists participants_read on booking.booking_participants;
create policy participants_read on booking.booking_participants
  for select to authenticated
  using (user_id = (select auth.uid()) or booking.is_booking_member(booking_id) or booking.is_booking_host(booking_id));

-- Host laedt ein; ausserdem darf sich jeder selbst einem offenen Match anschliessen.
drop policy if exists participants_insert on booking.booking_participants;
create policy participants_insert on booking.booking_participants
  for insert to authenticated
  with check (
    booking.is_booking_host(booking_id)
    or (
      user_id = (select auth.uid())
      and not is_host
      and exists (
        select 1 from booking.open_matches om
        where om.booking_id = booking_participants.booking_id
          and om.status = 'open'
          and om.visibility = 'public'
      )
    )
  );

drop policy if exists participants_update on booking.booking_participants;
create policy participants_update on booking.booking_participants
  for update to authenticated
  using (user_id = (select auth.uid()) or booking.is_booking_host(booking_id))
  with check (user_id = (select auth.uid()) or booking.is_booking_host(booking_id));

drop policy if exists participants_delete on booking.booking_participants;
create policy participants_delete on booking.booking_participants
  for delete to authenticated
  using ((user_id = (select auth.uid()) and not is_host) or booking.is_booking_host(booking_id));

-- -----------------------------------------------------------------------------
-- Open Matches
-- -----------------------------------------------------------------------------
-- Oeffentlich lesbar: genau das ist der Matchmaking-Hebel.
drop policy if exists open_matches_read on booking.open_matches;
create policy open_matches_read on booking.open_matches
  for select to anon, authenticated
  using (
    (status <> 'cancelled' and visibility = 'public')
    or booking.is_booking_member(booking_id)
    or booking.is_booking_host(booking_id)
  );

drop policy if exists open_matches_write on booking.open_matches;
create policy open_matches_write on booking.open_matches
  for all to authenticated
  using (booking.is_booking_host(booking_id))
  with check (booking.is_booking_host(booking_id));

-- -----------------------------------------------------------------------------
-- Ereignisse & Zahlungen (nur lesen; geschrieben wird per Trigger/service_role)
-- -----------------------------------------------------------------------------
drop policy if exists booking_events_read on booking.booking_events;
create policy booking_events_read on booking.booking_events
  for select to authenticated
  using (booking.is_booking_member(booking_id) or booking.is_booking_host(booking_id));

drop policy if exists payments_read on booking.payments;
create policy payments_read on booking.payments
  for select to authenticated
  using (user_id = (select auth.uid()) or booking.is_booking_host(booking_id));
