-- =============================================================================
-- Playindex · Preisabfrage fuer Clients absichern
-- =============================================================================
-- booking.calculate_price(..., p_user_id) nimmt eine beliebige user_id
-- entgegen. Fuer Trigger und Serverkontext ist das noetig (Personal bucht fuer
-- ein Mitglied), aus dem Browser waere es ein kleines Orakel: der Mitglieds-
-- preis unterscheidet sich vom Gastpreis und verraet damit den Tarif fremder
-- Nutzer.
--
-- Deshalb: die parametrisierte Variante bleibt intern, Clients bekommen einen
-- Wrapper ohne user_id, der immer auth.uid() verwendet.
-- =============================================================================

set search_path = public, extensions;

create or replace function booking.price_for_me(
  p_court_id  uuid,
  p_starts_at timestamptz,
  p_ends_at   timestamptz
) returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select booking.calculate_price(p_court_id, p_starts_at, p_ends_at, (select auth.uid()));
$$;

comment on function booking.price_for_me(uuid, timestamptz, timestamptz) is
  'Preis fuer den aufrufenden Nutzer. Einzige Preisfunktion, die anon/authenticated ausfuehren duerfen.';

revoke all on function booking.calculate_price(uuid, timestamptz, timestamptz, uuid)
  from public, anon, authenticated;

revoke all on function booking.price_for_me(uuid, timestamptz, timestamptz) from public;
grant execute on function booking.price_for_me(uuid, timestamptz, timestamptz)
  to anon, authenticated;
