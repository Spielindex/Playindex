-- =============================================================================
-- Playindex · Fundament
-- Extensions, Schemas, Enums, generische Helfer
-- =============================================================================
-- Konventionen:
--   * Alle Buchungsdaten liegen im Schema `booking` (NICHT in `public`).
--     Grund: Playindex teilt sich das Supabase-Projekt mit PadelIndex/TennisIndex.
--     `public` gehoert dem zentralen Index-Oekosystem, `booking` gehoert uns.
--     -> Keine Namenskollisionen, getrennte Grants, klare Ownership-Grenze.
--   * `booking` muss im Supabase Dashboard unter
--     Settings -> API -> "Exposed schemas" ergaenzt werden,
--     damit PostgREST/supabase-js darauf zugreifen kann.
--   * Alle Migrationen sind idempotent (re-runnable im SQL-Editor).
-- =============================================================================

create schema if not exists extensions;

create extension if not exists btree_gist with schema extensions;  -- uuid = im EXCLUDE-Constraint
create extension if not exists pgcrypto  with schema extensions;   -- sha256 + Zufallstokens fuer SSO

-- Damit die gist-Operatorklassen aus `extensions` beim DDL gefunden werden.
set search_path = public, extensions;

create schema if not exists booking;
create schema if not exists sso;

comment on schema booking is 'Playindex Platzbuchung (Clubs, Plaetze, Buchungen, Open Matches, Zahlungen).';
comment on schema sso     is 'Cross-Domain Session-Handoff zwischen padelindex.de / tennisindex.eu / playindex.de. Nicht ueber PostgREST exponieren.';

grant usage on schema booking to anon, authenticated, service_role;
grant usage on schema sso     to service_role;

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
do $$ begin create type booking.sport as enum ('padel','tennis');
exception when duplicate_object then null; end $$;

do $$ begin create type booking.booking_status as enum ('pending','confirmed','cancelled','no_show','completed');
exception when duplicate_object then null; end $$;

-- 'player'       = normale Spielerbuchung
-- 'subscription' = Abo / Dauerbuchung
-- 'course'       = Training / Kurs
-- 'tournament'   = Turnier
-- 'maintenance'  = Sperrung (Wartung, Platzpflege)
do $$ begin create type booking.booking_type as enum ('player','subscription','course','tournament','maintenance');
exception when duplicate_object then null; end $$;

do $$ begin create type booking.membership_tier as enum ('guest','member','subscriber');
exception when duplicate_object then null; end $$;

do $$ begin create type booking.staff_role as enum ('owner','admin','staff');
exception when duplicate_object then null; end $$;

do $$ begin create type booking.participant_status as enum ('invited','accepted','declined');
exception when duplicate_object then null; end $$;

do $$ begin create type booking.payment_status as enum ('unpaid','pending','paid','refunded','waived');
exception when duplicate_object then null; end $$;

do $$ begin create type booking.open_match_status as enum ('open','full','closed','cancelled');
exception when duplicate_object then null; end $$;

do $$ begin create type booking.index_platform as enum ('padelindex','tennisindex');
exception when duplicate_object then null; end $$;

-- -----------------------------------------------------------------------------
-- Generische Helfer
-- -----------------------------------------------------------------------------
create or replace function booking.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Adapter-Helfer: liefert den ersten existierenden Spaltennamen aus einer
-- Kandidatenliste. Wird gebraucht, um das zentrale Profil-Schema von
-- PadelIndex/TennisIndex anzubinden, ohne dessen Spaltennamen zu kennen.
create or replace function booking.pick_column(p_schema text, p_table text, p_candidates text[])
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select c.column_name::text
  from information_schema.columns c
  where c.table_schema = p_schema
    and c.table_name   = p_table
    and c.column_name  = any(p_candidates)
  order by array_position(p_candidates, c.column_name::text)
  limit 1;
$$;

revoke all on function booking.pick_column(text, text, text[]) from public, anon, authenticated;
