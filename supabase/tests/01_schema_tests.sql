-- =============================================================================
-- Playindex - Verhaltenstests fuer das Buchungsschema
-- =============================================================================
-- Ausfuehren ueber ./supabase/tests/run.sh
-- Getestet werden: Preislogik, Doppelbuchungsschutz, Buchungsregeln, RLS-
-- Sichtbarkeit, Open-Match-Beitritt, anonymer Grid-Zugriff und SSO-Handoff.
-- =============================================================================

\set ON_ERROR_STOP off
\pset pager off

-- Zuruecksetzen, damit die Suite auch gegen eine bereits benutzte Datenbank
-- wiederholbar ist (run.sh baut ohnehin frisch auf, aber ein manueller
-- Wiederholungslauf soll nicht falsche Fehler melden).
truncate booking.booking_events, booking.booking_participants, booking.open_matches,
         booking.payments, booking.bookings, booking.club_members cascade;
delete from sso.identity_links;
delete from sso.handoff_tokens;
delete from sso.request_nonces;

-- Testnutzer
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111','alex@example.com'),
  ('22222222-2222-2222-2222-222222222222','bea@example.com')
on conflict (id) do update
  set email = excluded.email, email_confirmed_at = now();
insert into public.profiles (id, display_name, padel_elo) values
  ('11111111-1111-1111-1111-111111111111','Alex', 1450.0),
  ('22222222-2222-2222-2222-222222222222','Bea',  1380.0)
on conflict do nothing;

-- Testzeitpunkt: naechster Dienstag (dow=2 -> Primetime-Regel greift)
create or replace function pg_temp.slot(h int, m int default 0) returns timestamptz
language sql stable as $$
  select ((date_trunc('week', current_date)::date + 8)::text || ' ' ||
          lpad(h::text,2,'0') || ':' || lpad(m::text,2,'0'))::timestamp
         at time zone 'Europe/Berlin';
$$;

create or replace function pg_temp.court(s text) returns uuid
language sql stable as $$ select id from booking.courts where slug = s $$;

create or replace function pg_temp.try(label text, stmt text) returns void
language plpgsql as $$
begin
  execute stmt;
  raise notice '  [OK]   %', label;
exception when others then
  raise notice '  [FAIL] % -> %: %', label, sqlstate, sqlerrm;
end $$;

create or replace function pg_temp.expect_fail(label text, stmt text, expect text default null) returns void
language plpgsql as $$
begin
  execute stmt;
  raise notice '  [FAIL] % wurde faelschlich AKZEPTIERT', label;
exception when others then
  if expect is null or sqlstate = expect then
    raise notice '  [OK]   % korrekt abgelehnt (%)', label, sqlstate;
  else
    raise notice '  [FAIL] % abgelehnt, aber mit % statt %: %', label, sqlstate, expect, sqlerrm;
  end if;
end $$;

\echo ''
\echo '=== 1. Preisberechnung ueber Tarifgrenze (16:00-18:00 Padel, Di) ==='
select booking.calculate_price(pg_temp.court('padel-1'), pg_temp.slot(16), pg_temp.slot(18)) as gast_cents,
       '7200 erwartet (1h Grund 3200 + 1h Primetime 4000)' as erwartung;

\echo ''
\echo '=== 2. Buchung als Alex (mit Open Match) ==='
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', false);

select id, starts_at, price_cents from booking.create_booking(
  pg_temp.court('padel-1'), pg_temp.slot(16), pg_temp.slot(18), 4::smallint, 'Testbuchung',
  '{"enabled":true,"players_needed":2,"level_min":1300,"level_max":1600,"description":"Suchen 2 Mitspieler"}'::jsonb
);

\echo ''
\echo '=== 3. Regelverletzungen werden abgewiesen ==='
do $$
begin
  perform pg_temp.expect_fail('Doppelbuchung (gleicher Platz, gleiche Zeit)',
    format('select booking.create_booking(%L::uuid, %L::timestamptz, %L::timestamptz)',
           pg_temp.court('padel-1'), pg_temp.slot(16), pg_temp.slot(18)), '23P01');

  perform pg_temp.expect_fail('Ueberlappende Buchung (17:00-18:30)',
    format('select booking.create_booking(%L::uuid, %L::timestamptz, %L::timestamptz)',
           pg_temp.court('padel-1'), pg_temp.slot(17), pg_temp.slot(18,30)), '23P01');

  perform pg_temp.expect_fail('Ausserhalb der Oeffnungszeiten (05:00-06:00)',
    format('select booking.create_booking(%L::uuid, %L::timestamptz, %L::timestamptz)',
           pg_temp.court('padel-2'), pg_temp.slot(5), pg_temp.slot(6)));

  perform pg_temp.expect_fail('Nicht auf dem 30-Minuten-Raster (16:10)',
    format('select booking.create_booking(%L::uuid, %L::timestamptz, %L::timestamptz)',
           pg_temp.court('padel-2'), pg_temp.slot(16,10), pg_temp.slot(17,10)));

  perform pg_temp.expect_fail('Zu lang (07:00-12:00 = 300 min)',
    format('select booking.create_booking(%L::uuid, %L::timestamptz, %L::timestamptz)',
           pg_temp.court('padel-2'), pg_temp.slot(7), pg_temp.slot(12)));

  perform pg_temp.expect_fail('In der Vergangenheit',
    format('select booking.create_booking(%L::uuid, %L::timestamptz, %L::timestamptz)',
           pg_temp.court('padel-2'), now() - interval '2 days', now() - interval '2 days' + interval '1 hour'));

  perform pg_temp.expect_fail('Zu weit im Voraus (60 Tage)',
    format('select booking.create_booking(%L::uuid, %L::timestamptz, %L::timestamptz)',
           pg_temp.court('padel-2'), pg_temp.slot(16) + interval '60 days', pg_temp.slot(18) + interval '60 days'));

  perform pg_temp.try('Anderer Platz, gleiche Zeit ist erlaubt',
    format('select booking.create_booking(%L::uuid, %L::timestamptz, %L::timestamptz)',
           pg_temp.court('padel-2'), pg_temp.slot(16), pg_temp.slot(18)));

  perform pg_temp.expect_fail('Preis manipulieren',
    'update booking.bookings set price_cents = 1 where booked_by = auth.uid()');

  perform pg_temp.expect_fail('Umbuchen (Zeit aendern)',
    'update booking.bookings set starts_at = starts_at + interval ''1 hour'' where booked_by = auth.uid()');
end $$;

\echo ''
\echo '=== 4. RLS: Bea sieht Alex Buchung nicht, aber die Belegung ==='
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222', false);
select (select count(*) from booking.bookings)              as bea_sieht_buchungen,
       (select count(*) from booking.v_court_availability)  as bea_sieht_belegung,
       (select count(*) from booking.v_open_matches)        as bea_sieht_open_matches;

\echo ''
\echo '=== 5. Bea tritt dem offenen Match bei ==='
do $$
declare v_bid uuid;
begin
  select booking_id into v_bid from booking.v_open_matches limit 1;
  perform pg_temp.try('Beitritt zum offenen Match',
    format('insert into booking.booking_participants (booking_id, user_id, status) values (%L,%L,''accepted'')',
           v_bid, '22222222-2222-2222-2222-222222222222'));
  perform pg_temp.expect_fail('Beitritt als Host faelschen',
    format('insert into booking.booking_participants (booking_id, user_id, status, is_host) values (%L,%L,''accepted'',true)',
           v_bid, '22222222-2222-2222-2222-222222222222'));
end $$;

\echo ''
\echo '=== 6. Anonymes Grid (ohne Login) ==='
reset role;
select set_config('request.jwt.claim.sub','', false);
set role anon;
select (select count(*) from booking.v_court_availability) as anon_sieht_belegung;
do $$ begin
  perform pg_temp.expect_fail('anon liest booking.bookings direkt',
    'select count(*) from booking.bookings');
end $$;

select jsonb_pretty(jsonb_build_object(
  'club',    booking.get_day_schedule('sportcenter-hahn', (date_trunc('week', current_date)::date + 8), 'padel')->'club'->>'name',
  'courts',  jsonb_array_length(booking.get_day_schedule('sportcenter-hahn', (date_trunc('week', current_date)::date + 8), 'padel')->'courts'),
  'padel_1', booking.get_day_schedule('sportcenter-hahn', (date_trunc('week', current_date)::date + 8), 'padel')->'courts'->0
)) as tagesplan_auszug;

\echo ''
\echo '=== 7. Mitgliederpreis ==='
reset role;
insert into booking.club_members (club_id, user_id, tier)
select id, '11111111-1111-1111-1111-111111111111', 'member' from booking.clubs where slug='sportcenter-hahn'
on conflict do nothing;
select booking.calculate_price(pg_temp.court('padel-1'), pg_temp.slot(16), pg_temp.slot(18),
                               '11111111-1111-1111-1111-111111111111') as mitglied_cents,
       '5400 erwartet (2400 + 3000)' as erwartung;

\echo ''
\echo '=== 8. SSO Handoff ==='
do $$
declare v_token text; v_uid uuid; v_second uuid;
begin
  v_token := sso.issue_handoff_token('11111111-1111-1111-1111-111111111111','padelindex','/buchen');
  raise notice '  Ticket ausgegeben (Laenge %, wird nur gehasht gespeichert)', length(v_token);

  select user_id into v_uid from sso.consume_handoff_token(v_token);
  if v_uid = '11111111-1111-1111-1111-111111111111' then
    raise notice '  [OK]   Ticket eingeloest -> korrekter Nutzer';
  else
    raise notice '  [FAIL] falscher Nutzer: %', v_uid;
  end if;

  select user_id into v_second from sso.consume_handoff_token(v_token);
  if v_second is null then
    raise notice '  [OK]   Replay abgewiesen (Ticket ist einmalig)';
  else
    raise notice '  [FAIL] Ticket war mehrfach einloesbar!';
  end if;

  update sso.handoff_tokens set consumed_at = null, expires_at = now() - interval '1 second';
  select user_id into v_second from sso.consume_handoff_token(v_token);
  if v_second is null then
    raise notice '  [OK]   Abgelaufenes Ticket abgewiesen';
  else
    raise notice '  [FAIL] Abgelaufenes Ticket akzeptiert!';
  end if;

  if not exists (select 1 from sso.handoff_tokens where token_hash = v_token) then
    raise notice '  [OK]   Rohtoken steht nirgends in der Tabelle';
  end if;
end $$;

\echo ''
\echo '=== 9. Stornofrist ==='
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111', false);
do $$
declare v_bid uuid;
begin
  select b.id into v_bid from booking.bookings b join booking.open_matches om on om.booking_id=b.id where b.booked_by = auth.uid() limit 1;
  perform pg_temp.try('Storno ausserhalb der Frist erlaubt',
    format('select booking.cancel_booking(%L, ''Testabsage'')', v_bid));
end $$;

reset role;
select b.status, b.cancelled_at is not null as storniert, om.status as match_status
from booking.bookings b left join booking.open_matches om on om.booking_id=b.id
where b.status='cancelled';

select event, payload from booking.booking_events order by id;

\echo ''
\echo '=== 10. Identitaets-Bruecke zwischen zwei Projekten ==='
reset role;
select set_config('request.jwt.claim.sub','', false);
do $$
declare v_uid uuid; v_new uuid;
begin
  -- Unbestaetigte Mail darf NICHT automatisch verknuepft werden
  update auth.users set email_confirmed_at = null where email = 'alex@example.com';
  v_uid := sso.resolve_identity('tennisindex','tx-1','alex@example.com');
  if v_uid is null then
    raise notice '  [OK]   unbestaetigte E-Mail wird nicht auto-verknuepft';
  else
    raise notice '  [FAIL] unbestaetigte E-Mail wurde verknuepft!';
  end if;

  update auth.users set email_confirmed_at = now() where email = 'alex@example.com';
  v_uid := sso.resolve_identity('tennisindex','tx-1','alex@example.com');
  if v_uid = '11111111-1111-1111-1111-111111111111' then
    raise notice '  [OK]   bestaetigte E-Mail wird verknuepft';
  else
    raise notice '  [FAIL] Verknuepfung fehlgeschlagen: %', v_uid;
  end if;

  -- Zweiter Aufruf trifft die Verknuepfung, nicht mehr die E-Mail
  update auth.users set email = 'alex+neu@example.com' where id = '11111111-1111-1111-1111-111111111111';
  v_uid := sso.resolve_identity('tennisindex','tx-1', null);
  if v_uid = '11111111-1111-1111-1111-111111111111' then
    raise notice '  [OK]   Verknuepfung ueberlebt E-Mail-Wechsel';
  else
    raise notice '  [FAIL] Verknuepfung verloren';
  end if;

  update auth.users set email = 'alex@example.com' where id = '11111111-1111-1111-1111-111111111111';

  -- Unbekanntes Quellkonto -> NULL (Aufrufer legt per Admin-API an)
  if sso.resolve_identity('tennisindex','tx-999','niemand@example.com') is null then
    raise notice '  [OK]   unbekanntes Quellkonto liefert NULL';
  else
    raise notice '  [FAIL] unbekanntes Quellkonto aufgeloest';
  end if;

  -- Nonce: einmal true, dann false. Zufaellig, damit der Test wiederholbar ist.
  declare v_nonce text := gen_random_uuid()::text;
  begin
    if sso.claim_nonce(v_nonce,'tennisindex') and not sso.claim_nonce(v_nonce,'tennisindex') then
      raise notice '  [OK]   Nonce-Replay abgewiesen';
    else
      raise notice '  [FAIL] Nonce-Replay moeglich';
    end if;
  end;
end $$;

\echo ''
\echo '=== 11. Preisabfrage ist nicht als Orakel missbrauchbar ==='
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222', false);
do $$
begin
  perform pg_temp.expect_fail('calculate_price mit fremder user_id',
    format('select booking.calculate_price(%L::uuid, %L::timestamptz, %L::timestamptz, %L::uuid)',
           pg_temp.court('padel-1'), pg_temp.slot(16), pg_temp.slot(18),
           '11111111-1111-1111-1111-111111111111'), '42501');
  perform pg_temp.try('price_for_me ohne Parameter',
    format('select booking.price_for_me(%L::uuid, %L::timestamptz, %L::timestamptz)',
           pg_temp.court('padel-1'), pg_temp.slot(16), pg_temp.slot(18)));
end $$;
reset role;
