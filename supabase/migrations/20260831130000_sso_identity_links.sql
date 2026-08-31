-- =============================================================================
-- Playindex · Identitaets-Bruecke zwischen zwei Supabase-Projekten
-- =============================================================================
-- AUSGANGSLAGE
-- padelindex.de und tennisindex.eu laufen heute auf ZWEI getrennten Supabase-
-- Projekten. Playindex zieht in das groessere der beiden ein (= "Identity-
-- Projekt"). Fuer dessen Nutzer ist Cross-Login damit sofort geloest.
--
-- Fuer das ZWEITE Projekt braucht es bis zum Cutover eine Zuordnung:
--   (Quellprojekt, dortige user_id)  ->  user_id im Identity-Projekt
--
-- Genau das ist `sso.identity_links`. Nach der Konsolidierung bleibt die
-- Tabelle nur noch als Historie stehen; der Partner-Endpunkt entfaellt.
--
-- VERTRAUENSGRENZE (bewusst benannt)
-- Ein Partner, der ein Ticket anfordert, behauptet "das ist Nutzer X mit
-- E-Mail Y". Dieses Vertrauen ist genau so gross wie das Vertrauen in den
-- Session-Speicher des Partners - das ist bei jeder Foederation so. Deshalb:
--   * pro Partner ein eigenes HMAC-Secret (kompromittierter Partner reisst
--     nicht das ganze System mit)
--   * Verknuepfung ueber E-Mail nur, wenn diese im Identity-Projekt bestaetigt ist
--   * jede Verknuepfung ist protokolliert und auditierbar
-- =============================================================================

set search_path = public, extensions;

create table if not exists sso.identity_links (
  source           text        not null,   -- 'padelindex' | 'tennisindex'
  external_user_id text        not null,   -- user_id im Quellprojekt
  user_id          uuid        not null references auth.users(id) on delete cascade,
  email_at_link    text,
  link_method      text        not null default 'email',  -- 'email' | 'created' | 'manual'
  linked_at        timestamptz not null default now(),
  last_seen_at     timestamptz,

  primary key (source, external_user_id),
  unique (source, user_id)                 -- ein Quellkonto je Identitaet und Projekt
);

create index if not exists identity_links_user_idx on sso.identity_links (user_id);

alter table sso.identity_links enable row level security;
revoke all on sso.identity_links from public, anon, authenticated;
grant all on sso.identity_links to service_role;

-- -----------------------------------------------------------------------------
-- Replay-Schutz fuer signierte Partner-Requests
-- -----------------------------------------------------------------------------
create table if not exists sso.request_nonces (
  nonce   text        primary key,
  source  text        not null,
  seen_at timestamptz not null default now()
);

create index if not exists request_nonces_seen_idx on sso.request_nonces (seen_at);

alter table sso.request_nonces enable row level security;
revoke all on sso.request_nonces from public, anon, authenticated;
grant all on sso.request_nonces to service_role;

-- Gibt true zurueck, wenn die Nonce neu war. Das INSERT selbst ist die Pruefung.
create or replace function sso.claim_nonce(p_nonce text, p_source text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into sso.request_nonces (nonce, source) values (p_nonce, p_source);
  return true;
exception when unique_violation then
  return false;
end $$;

-- -----------------------------------------------------------------------------
-- Identitaet aufloesen
-- -----------------------------------------------------------------------------
-- Reihenfolge:
--   1. bestehende Verknuepfung  -> direkt zurueck
--   2. bestaetigte E-Mail im Identity-Projekt -> verknuepfen und zurueck
--   3. NULL -> der Aufrufer legt den Nutzer per Admin-API an und ruft
--      sso.link_identity(). Nutzer werden bewusst NICHT in SQL erzeugt,
--      damit GoTrue seine eigenen Identity-Datensaetze sauber anlegt.
create or replace function sso.resolve_identity(
  p_source           text,
  p_external_user_id text,
  p_email            text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  select l.user_id into v_user_id
  from sso.identity_links l
  where l.source = p_source and l.external_user_id = p_external_user_id;

  if v_user_id is not null then
    update sso.identity_links
    set last_seen_at = now()
    where source = p_source and external_user_id = p_external_user_id;
    return v_user_id;
  end if;

  if p_email is null then
    return null;
  end if;

  select u.id into v_user_id
  from auth.users u
  where lower(u.email) = lower(p_email)
    and u.email_confirmed_at is not null
  limit 1;

  if v_user_id is null then
    return null;
  end if;

  insert into sso.identity_links (source, external_user_id, user_id, email_at_link, link_method, last_seen_at)
  values (p_source, p_external_user_id, v_user_id, lower(p_email), 'email', now())
  on conflict (source, external_user_id) do update set last_seen_at = now();

  return v_user_id;
end $$;

create or replace function sso.link_identity(
  p_source           text,
  p_external_user_id text,
  p_user_id          uuid,
  p_email            text default null,
  p_method           text default 'created'
) returns void
language sql
security definer
set search_path = ''
as $$
  insert into sso.identity_links (source, external_user_id, user_id, email_at_link, link_method, last_seen_at)
  values (p_source, p_external_user_id, p_user_id, lower(p_email), p_method, now())
  on conflict (source, external_user_id)
    do update set user_id = excluded.user_id, last_seen_at = now();
$$;

-- Aufraeumen: abgelaufene Tickets und alte Nonces.
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
  delete from sso.request_nonces where seen_at < now() - interval '1 hour';
  return v_deleted;
end $$;

revoke all on function sso.claim_nonce(text, text)                        from public, anon, authenticated;
revoke all on function sso.resolve_identity(text, text, text)             from public, anon, authenticated;
revoke all on function sso.link_identity(text, text, uuid, text, text)    from public, anon, authenticated;

grant execute on function sso.claim_nonce(text, text)                     to service_role;
grant execute on function sso.resolve_identity(text, text, text)          to service_role;
grant execute on function sso.link_identity(text, text, uuid, text, text) to service_role;
