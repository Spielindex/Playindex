import { json, type RequestHandler } from '@sveltejs/kit';
import { PUBLIC_SITE_URL } from '$env/static/public';
import { ssoAdmin, supabaseAdmin } from '$lib/server/supabase-admin';
import { partnerSecret, signaturPruefen, sicheresZiel, zeitstempelGueltig } from '$lib/server/sso';

/**
 * Server-zu-Server: padelindex.de / tennisindex.eu holen hier ein Handoff-Ticket.
 *
 *   POST /api/sso/ticket
 *   x-playindex-partner:   tennisindex
 *   x-playindex-timestamp: 1756600000
 *   x-playindex-nonce:     <zufaellig, einmalig>
 *   x-playindex-signature: sha256=<hmac(ts.nonce.body)>
 *   { "external_user_id": "…", "email": "…", "redirect_to": "/buchen/sportcenter-hahn" }
 *
 *   -> { "url": "https://playindex.de/auth/handoff?t=…" }
 *
 * Der Partner leitet den Nutzer anschliessend auf diese URL weiter.
 *
 * Der Partner sieht nie ein Supabase-Key. Er besitzt nur sein eigenes
 * HMAC-Secret und kann damit ausschliesslich Tickets fuer Nutzer anfordern -
 * keine Daten lesen, nichts schreiben.
 */
export const POST: RequestHandler = async ({ request, getClientAddress }) => {
  const quelle = request.headers.get('x-playindex-partner') ?? '';
  const timestamp = request.headers.get('x-playindex-timestamp') ?? '';
  const nonce = request.headers.get('x-playindex-nonce') ?? '';
  const signatur = request.headers.get('x-playindex-signature') ?? '';

  const secret = partnerSecret(quelle);
  // Einheitliche Antwort fuer "Partner unbekannt" und "Signatur falsch" -
  // sonst wird der Endpunkt zum Orakel fuer gueltige Partnernamen.
  const abgelehnt = () => json({ error: 'unauthorized' }, { status: 401 });

  if (!secret || !timestamp || !nonce || !signatur) return abgelehnt();
  if (!zeitstempelGueltig(timestamp)) return abgelehnt();

  const rawBody = await request.text();
  if (rawBody.length > 4096) return abgelehnt();
  if (!(await signaturPruefen({ secret, timestamp, nonce, rawBody, signature: signatur }))) {
    return abgelehnt();
  }

  // Replay-Schutz: die Nonce wird in der DB beansprucht, das INSERT ist die Pruefung.
  const { data: nonceFrei, error: nonceFehler } = await ssoAdmin.rpc('claim_nonce', {
    p_nonce: nonce,
    p_source: quelle
  });
  if (nonceFehler || !nonceFrei) return abgelehnt();

  let payload: { external_user_id?: string; email?: string; redirect_to?: string };
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return json({ error: 'bad_request' }, { status: 400 });
  }

  const externeId = payload.external_user_id?.trim();
  const email = payload.email?.trim().toLowerCase() || null;
  if (!externeId) return json({ error: 'external_user_id fehlt' }, { status: 400 });

  // 1. Bestehende Verknuepfung oder bestaetigte E-Mail
  const { data: aufgeloest, error: resolveFehler } = await ssoAdmin.rpc('resolve_identity', {
    p_source: quelle,
    p_external_user_id: externeId,
    p_email: email
  });
  if (resolveFehler) return json({ error: 'resolve_failed' }, { status: 500 });

  let userId = aufgeloest;

  // 2. Noch keine Identitaet im Identity-Projekt -> anlegen und verknuepfen.
  //    Nutzer werden ueber die Admin-API erzeugt, nicht per SQL, damit GoTrue
  //    seine eigenen Identity-Datensaetze sauber mit anlegt.
  if (!userId) {
    if (!email) return json({ error: 'email_required' }, { status: 400 });

    const { data: neu, error: createFehler } = await supabaseAdmin.auth.admin.createUser({
      email,
      email_confirm: true,
      user_metadata: { angelegt_ueber: quelle }
    });
    if (createFehler || !neu.user) return json({ error: 'create_failed' }, { status: 500 });

    userId = neu.user.id;
    await ssoAdmin.rpc('link_identity', {
      p_source: quelle,
      p_external_user_id: externeId,
      p_user_id: userId,
      p_email: email,
      p_method: 'created'
    });
  }

  const ziel = sicheresZiel(payload.redirect_to, '/');

  const { data: ticket, error: ticketFehler } = await ssoAdmin.rpc('issue_handoff_token', {
    p_user_id: userId,
    p_issued_by: quelle,
    p_redirect_to: ziel,
    p_user_agent: request.headers.get('user-agent'),
    p_ip: getClientAddress()
  });
  if (ticketFehler || !ticket) return json({ error: 'issue_failed' }, { status: 500 });

  return json({
    url: `${PUBLIC_SITE_URL}/auth/handoff?t=${encodeURIComponent(ticket)}`,
    expires_in: 60
  });
};
