-- =============================================================================
-- Playindex · Identity-Bridge
-- Verbindung zwischen zentralem Index-Profil und lokalen Club-Daten
-- =============================================================================
-- KERNENTSCHEIDUNG
-- ----------------
-- Es gibt genau EINE Identitaet: `auth.users`. Playindex dupliziert weder
-- E-Mail, noch Name, noch Elo. Stattdessen:
--
--   auth.users            (zentral, Supabase Auth)   <- Single Source of Truth Identitaet
--     └─ public.profiles  (zentral, PadelIndex/TennisIndex) <- Name, Avatar, Elo
--          └─ booking.v_player  <- ADAPTER-VIEW (die einzige Kopplungsstelle)
--
--   booking.club_members  (lokal) <- NUR club-spezifische Attribute:
--                                    Mitgliedsnummer, Tarif, Rechnungsdaten,
--                                    Guthaben, No-Show-Zaehler.
--
-- Alles, was auf padelindex.de existiert, bleibt dort. Alles, was nur das
-- Sportcenter Hahn interessiert, liegt in club_members. Keine Spalte doppelt.
-- =============================================================================

set search_path = public, extensions;

-- -----------------------------------------------------------------------------
-- Fallback: minimales zentrales Profil, falls dieses Projekt (noch) keins hat
-- -----------------------------------------------------------------------------
-- Im geteilten Index-Projekt existiert public.profiles bereits -> dieser Block
-- macht nichts. In einem frischen Standalone-Projekt (lokale Entwicklung,
-- `supabase start`) wird ein Minimal-Profil angelegt, damit alles lauffaehig ist.
do $$
begin
  if to_regclass('public.profiles') is null then
    create table public.profiles (
      id           uuid primary key references auth.users(id) on delete cascade,
      display_name text,
      avatar_url   text,
      padel_elo    numeric(6,1),
      tennis_elo   numeric(6,1),
      created_at   timestamptz not null default now(),
      updated_at   timestamptz not null default now()
    );

    alter table public.profiles enable row level security;

    create policy profiles_select_all on public.profiles
      for select to authenticated using (true);
    create policy profiles_update_self on public.profiles
      for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
    create policy profiles_insert_self on public.profiles
      for insert to authenticated with check (id = (select auth.uid()));

    grant select, insert, update on public.profiles to authenticated;

    raise notice 'public.profiles war nicht vorhanden und wurde als Standalone-Fallback angelegt.';
  else
    raise notice 'public.profiles existiert bereits (zentrales Index-Profil) - keine Aenderung.';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- ADAPTER-VIEW  ·  die einzige Stelle, die das zentrale Profil-Schema kennt
-- -----------------------------------------------------------------------------
-- Wenn PadelIndex seine Spalten anders nennt (username statt display_name,
-- elo_padel statt padel_elo, user_id statt id ...), wird das hier automatisch
-- aufgeloest. Falls ein Name gar nicht in der Kandidatenliste steht: NUR diese
-- eine View anpassen - der Rest des Schemas bleibt unberuehrt.
do $$
declare
  v_join    text;
  v_display text;
  v_avatar  text;
  v_padel   text;
  v_tennis  text;
begin
  v_join    := booking.pick_column('public','profiles', array['id','user_id','profile_id','auth_user_id']);
  v_display := booking.pick_column('public','profiles', array['display_name','username','full_name','name','nickname']);
  v_avatar  := booking.pick_column('public','profiles', array['avatar_url','avatar','image_url','photo_url']);
  v_padel   := booking.pick_column('public','profiles', array['padel_elo','elo_padel','padel_rating','padel_index','elo']);
  v_tennis  := booking.pick_column('public','profiles', array['tennis_elo','elo_tennis','tennis_rating','tennis_index']);

  if v_join is null then
    raise exception 'public.profiles hat keine erkennbare Join-Spalte auf auth.users. Bitte booking.v_player manuell definieren.';
  end if;

  execute format($f$
    create or replace view booking.v_player as
    select
      u.id                                       as user_id,
      coalesce(%s, 'Spieler')                    as display_name,
      %s                                         as avatar_url,
      %s                                         as padel_elo,
      %s                                         as tennis_elo
    from auth.users u
    left join public.profiles p on p.%I = u.id
  $f$,
    coalesce('p.' || quote_ident(v_display), 'null::text'),
    coalesce('p.' || quote_ident(v_avatar),  'null::text'),
    coalesce('p.' || quote_ident(v_padel),   'null::numeric'),
    coalesce('p.' || quote_ident(v_tennis),  'null::numeric'),
    v_join
  );
end $$;

comment on view booking.v_player is
  'Adapter auf das zentrale Index-Profil. EINZIGE Kopplungsstelle an public.profiles. Bewusst SECURITY DEFINER (Standard), da auth.users fuer authenticated nicht lesbar ist - deshalb wird hier NIEMALS die E-Mail exponiert.';

-- Kein anon-Zugriff: Spielernamen sind nur fuer eingeloggte Nutzer sichtbar.
revoke all on booking.v_player from public;
grant select on booking.v_player to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Club-Team (Rollen fuer Betreiber/Personal)
-- -----------------------------------------------------------------------------
create table if not exists booking.club_staff (
  club_id    uuid              not null references booking.clubs(id) on delete cascade,
  user_id    uuid              not null references auth.users(id)    on delete cascade,
  role       booking.staff_role not null default 'staff',
  created_at timestamptz        not null default now(),
  primary key (club_id, user_id)
);

-- -----------------------------------------------------------------------------
-- Lokale Clubdaten  ·  KEINE Duplikate des zentralen Profils
-- -----------------------------------------------------------------------------
create table if not exists booking.club_members (
  club_id        uuid                   not null references booking.clubs(id) on delete cascade,
  user_id        uuid                   not null references auth.users(id)    on delete cascade,
  tier           booking.membership_tier not null default 'guest',
  member_number  text,
  phone          text,
  invoice_email  text,                  -- abweichende Rechnungsadresse (Login-Mail bleibt zentral)
  invoice_name   text,
  invoice_street text,
  invoice_zip    text,
  invoice_city   text,
  credit_cents   integer                not null default 0,
  no_show_count  smallint               not null default 0,
  is_blocked     boolean                not null default false,
  joined_at      timestamptz            not null default now(),
  updated_at     timestamptz            not null default now(),

  primary key (club_id, user_id),
  unique (club_id, member_number)
);

comment on table booking.club_members is
  'Ausschliesslich club-lokale Attribute. Name/Avatar/Elo kommen aus booking.v_player, niemals von hier.';

drop trigger if exists trg_club_members_touch on booking.club_members;
create trigger trg_club_members_touch before update on booking.club_members
  for each row execute function booking.touch_updated_at();

-- Interne Notizen strikt getrennt: RLS kann keine Spalten filtern,
-- also bekommen Personal-Notizen eine eigene Tabelle mit eigener Policy.
create table if not exists booking.club_member_notes (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid        not null,
  user_id    uuid        not null,
  author_id  uuid                 references auth.users(id) on delete set null,
  note       text        not null,
  created_at timestamptz not null default now(),

  foreign key (club_id, user_id) references booking.club_members(club_id, user_id) on delete cascade
);

-- -----------------------------------------------------------------------------
-- Berechtigungs-Helfer
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER + fully qualified: laeuft als Owner, umgeht damit RLS auf
-- club_staff und verhindert so Policy-Rekursion.
create or replace function booking.is_club_staff(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from booking.club_staff s
    where s.club_id = p_club_id
      and s.user_id = (select auth.uid())
  );
$$;

create or replace function booking.has_club_role(p_club_id uuid, p_roles booking.staff_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from booking.club_staff s
    where s.club_id = p_club_id
      and s.user_id = (select auth.uid())
      and s.role = any(p_roles)
  );
$$;

create or replace function booking.is_club_member(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from booking.club_members m
    where m.club_id = p_club_id
      and m.user_id = (select auth.uid())
      and m.tier in ('member','subscriber')
      and not m.is_blocked
  );
$$;

grant execute on function booking.is_club_staff(uuid)                        to authenticated;
grant execute on function booking.has_club_role(uuid, booking.staff_role[])  to authenticated;
grant execute on function booking.is_club_member(uuid)                       to authenticated;
