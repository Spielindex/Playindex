-- =============================================================================
-- Playindex · Startdaten "Sportcenter Hahn"
-- =============================================================================
-- ACHTUNG: Platzanzahl, Belaege, Oeffnungszeiten und Preise sind PLATZHALTER.
-- Bitte vor dem Livegang durch die echten Werte des Sportcenters ersetzen.
-- Die Datei ist idempotent und kann jederzeit erneut ausgefuehrt werden.
-- =============================================================================

set search_path = public, extensions;

insert into booking.clubs (
  slug, name, timezone, city, country, currency,
  slot_minutes, min_duration_minutes, max_duration_minutes,
  max_advance_days, cancellation_deadline_hours, max_open_bookings_per_user
)
values (
  'sportcenter-hahn', 'Sportcenter Hahn', 'Europe/Berlin', NULL, 'DE', 'EUR',
  30, 60, 180, 14, 24, 4
)
on conflict (slug) do nothing;

do $$
declare
  v_club uuid;
  v_i    integer;
  v_d    integer;
begin
  select id into v_club from booking.clubs where slug = 'sportcenter-hahn';

  -- --- Plaetze ---------------------------------------------------------------
  for v_i in 1..4 loop
    insert into booking.courts (club_id, slug, name, sport, surface, is_indoor, max_players, sort_order)
    values (v_club, 'padel-' || v_i, 'Padel ' || v_i, 'padel', 'sand', true, 4, v_i)
    on conflict (club_id, slug) do nothing;
  end loop;

  for v_i in 1..6 loop
    insert into booking.courts (club_id, slug, name, sport, surface, is_indoor, max_players, sort_order)
    values (v_club, 'tennis-' || v_i, 'Tennis ' || v_i, 'tennis',
            case when v_i <= 3 then 'teppich' else 'asche' end,
            v_i <= 3, 4, 10 + v_i)
    on conflict (club_id, slug) do nothing;
  end loop;

  -- --- Oeffnungszeiten: taeglich 07:00 - 23:00 -------------------------------
  for v_d in 0..6 loop
    if not exists (
      select 1 from booking.opening_hours
      where club_id = v_club and weekday = v_d and court_id is null
    ) then
      insert into booking.opening_hours (club_id, weekday, opens_at, closes_at)
      values (v_club, v_d, '07:00', '23:00');
    end if;
  end loop;

  -- --- Preise ---------------------------------------------------------------
  -- Grundtarif je Sportart (priority 0), Primetime Mo-Fr 17-22 Uhr (priority 10)
  if not exists (select 1 from booking.pricing_rules where club_id = v_club) then
    insert into booking.pricing_rules
      (club_id, sport, weekday, starts_at, ends_at, price_per_hour_cents, member_price_per_hour_cents, priority, label)
    values
      (v_club, 'padel',  null, '00:00', '24:00', 3200, 2400,  0, 'Padel Grundtarif'),
      (v_club, 'tennis', null, '00:00', '24:00', 2000, 1400,  0, 'Tennis Grundtarif');

    for v_d in 1..5 loop   -- Montag(1) bis Freitag(5)
      insert into booking.pricing_rules
        (club_id, sport, weekday, starts_at, ends_at, price_per_hour_cents, member_price_per_hour_cents, priority, label)
      values
        (v_club, 'padel',  v_d, '17:00', '22:00', 4000, 3000, 10, 'Padel Primetime'),
        (v_club, 'tennis', v_d, '17:00', '22:00', 2600, 1800, 10, 'Tennis Primetime');
    end loop;
  end if;
end $$;
