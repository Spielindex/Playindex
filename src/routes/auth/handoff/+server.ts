import { redirect, type RequestHandler } from '@sveltejs/kit';
import { ssoAdmin, supabaseAdmin } from '$lib/server/supabase-admin';
import { sicheresZiel } from '$lib/server/sso';

/**
 * Loest ein Handoff-Ticket gegen eine echte Playindex-Session ein.
 *
 * Der Nutzer landet hier per 302 von padelindex.de / tennisindex.eu und sieht
 * nichts von dieser Route - nur das Buchungsgrid, eingeloggt.
 *
 * Ablauf:
 *   1. Ticket einloesen (atomar, einmalig, 60 s - erzwungen in der DB)
 *   2. Zur user_id die E-Mail holen
 *   3. Magic-Link-Token serverseitig erzeugen und sofort selbst einloesen
 *   4. Cookies sind gesetzt -> weiter zum Ziel, ohne Ticket in der URL
 *
 * Der Magic-Link verlaesst nie den Server; er ersetzt nur den Schritt, fuer den
 * Supabase sonst eine E-Mail verschicken wuerde.
 */
export const GET: RequestHandler = async ({ url, locals, setHeaders }) => {
  // Verhindert, dass das Ticket ueber den Referer zu Dritten abfliesst.
  setHeaders({ 'referrer-policy': 'no-referrer', 'cache-control': 'no-store' });

  const ticket = url.searchParams.get('t');
  if (!ticket) redirect(303, '/login?fehler=handoff');

  const { data: zeilen, error: einloeseFehler } = await ssoAdmin.rpc('consume_handoff_token', {
    p_token: ticket
  });
  const treffer = zeilen?.[0];
  if (einloeseFehler || !treffer) {
    // Abgelaufen, schon benutzt oder gefaelscht - alle drei enden gleich.
    redirect(303, '/login?fehler=handoff_abgelaufen');
  }

  const { data: nutzer, error: nutzerFehler } = await supabaseAdmin.auth.admin.getUserById(
    treffer.user_id
  );
  if (nutzerFehler || !nutzer.user?.email) redirect(303, '/login?fehler=handoff');

  const { data: link, error: linkFehler } = await supabaseAdmin.auth.admin.generateLink({
    type: 'magiclink',
    email: nutzer.user.email
  });
  if (linkFehler || !link.properties?.hashed_token) redirect(303, '/login?fehler=handoff');

  // verifyOtp auf dem request-gebundenen Client -> setzt die sb-Cookies
  // auf playindex.de.
  const { error: otpFehler } = await locals.supabase.auth.verifyOtp({
    type: 'magiclink',
    token_hash: link.properties.hashed_token
  });
  if (otpFehler) redirect(303, '/login?fehler=handoff');

  redirect(303, sicheresZiel(treffer.redirect_to, '/'));
};
