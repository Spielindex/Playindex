-- =============================================================================
-- Playindex · Cross-Domain Session-Handoff
-- =============================================================================
-- PROBLEM
-- padelindex.de, tennisindex.eu und playindex.de sind drei verschiedene
-- eTLD+1-Domains. Ein Cookie von padelindex.de ist auf playindex.de
-- grundsaetzlich nicht lesbar - daran aendert auch ein geteiltes Supabase-
-- Projekt nichts. "Gleiches Login" und "gleiche Session" sind zwei Probleme:
--
--   1. Gleiche Credentials  -> geloest durch EIN gemeinsames Auth-Projekt.
--                              Dieselbe E-Mail + dasselbe Passwort funktionieren
--                              auf allen drei Domains. Kein Code noetig.
--
--   2. Kein zweites Login   -> geloest durch diesen kurzlebigen Handoff:
--      (nahtloser Wechsel)     padelindex.de gibt ein Einmal-Ticket aus,
--                              playindex.de loest es gegen eine eigene Session ein.
--
-- SICHERHEITSMODELL
--   * Nur der SHA-256-Hash des Tickets liegt in der DB - ein Datenbank-Leak
--     erlaubt keine Anmeldung.
--   * TTL 60 Sekunden, strikt einmalig einloesbar (atomares UPDATE ... RETURNING).
--   * Die Tabelle ist NICHT ueber PostgREST erreichbar (Schema `sso` wird nicht
--     exponiert); Ausgabe und Einloesung laufen ausschliesslich serverseitig
--     mit service_role.
--   * redirect_to wird gespeichert, aber muss beim Einloesen gegen eine
--     Allowlist im SvelteKit-Server geprueft werden (Open-Redirect-Schutz).
-- =============================================================================

set search_path = public, extensions;

create table if not exists sso.handoff_tokens (
  id          uuid primary key default gen_random_uuid(),
  token_hash  text        not null unique,        -- sha256(hex) des Rohtickets
  user_id     uuid        not null references auth.users(id) on delete cascade,
  issued_by   text        not null,               -- 'padelindex' | 'tennisindex' | 'playindex'
  audience    text        not null default 'playindex',
  redirect_to text,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '60 seconds',
  consumed_at timestamptz,
  user_agent  text,
  ip          inet
);

create index if not exists handoff_tokens_expiry_idx on sso.handoff_tokens (expires_at);
create index if not exists handoff_tokens_user_idx   on sso.handoff_tokens (user_id, created_at desc);

alter table sso.handoff_tokens enable row level security;
-- Bewusst KEINE Policy: nur service_role (BYPASSRLS) kommt heran.

revoke all on sso.handoff_tokens from public, anon, authenticated;
grant all on sso.handoff_tokens to service_role;

-- -----------------------------------------------------------------------------
-- Ticket ausgeben (auf padelindex.de / tennisindex.eu, serverseitig)
-- -----------------------------------------------------------------------------
create or replace function sso.issue_handoff_token(
  p_user_id     uuid,
  p_issued_by   text,
  p_redirect_to text default null,
  p_user_agent  text default null,
  p_ip          inet default null
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_raw text;
begin
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'Unbekannter Nutzer' using errcode = 'no_data_found';
  end if;

  -- 32 Byte Entropie, URL-sicher base64
  v_raw := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');

  insert into sso.handoff_tokens (token_hash, user_id, issued_by, redirect_to, user_agent, ip)
  values (
    encode(extensions.digest(v_raw, 'sha256'), 'hex'),
    p_user_id, p_issued_by, p_redirect_to, p_user_agent, p_ip
  );

  return v_raw;   -- wird NUR hier im Klartext gesehen und nie gespeichert
end $$;

-- -----------------------------------------------------------------------------
-- Ticket einloesen (auf playindex.de, serverseitig)
-- -----------------------------------------------------------------------------
-- Atomar: das UPDATE selbst ist die Einmal-Pruefung. Zwei parallele Requests
-- mit demselben Ticket -> genau einer bekommt eine Zeile zurueck.
create or replace function sso.consume_handoff_token(p_token text)
returns table (user_id uuid, redirect_to text, issued_by text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  update sso.handoff_tokens t
  set consumed_at = now()
  where t.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and t.consumed_at is null
    and t.expires_at > now()
  returning t.user_id, t.redirect_to, t.issued_by;
end $$;

create or replace function sso.purge_handoff_tokens()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_deleted integer;
begin
  delete from sso.handoff_tokens where expires_at < now() - interval '1 day';
  get diagnostics v_deleted = row_count;
  return v_deleted;
end $$;

revoke all on function sso.issue_handoff_token(uuid, text, text, text, inet) from public, anon, authenticated;
revoke all on function sso.consume_handoff_token(text)                       from public, anon, authenticated;
revoke all on function sso.purge_handoff_tokens()                            from public, anon, authenticated;

grant execute on function sso.issue_handoff_token(uuid, text, text, text, inet) to service_role;
grant execute on function sso.consume_handoff_token(text)                       to service_role;
grant execute on function sso.purge_handoff_tokens()                            to service_role;
