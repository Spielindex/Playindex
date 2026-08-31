/**
 * Gehoert in die PARTNER-App (padelindex.de / tennisindex.eu), nicht in
 * Playindex. Pfad dort z. B. src/routes/api/zu-playindex/+server.ts
 *
 * Holt serverseitig ein Handoff-Ticket bei Playindex und schickt den Nutzer
 * dorthin weiter. Der Nutzer sieht nur den Redirect.
 */
import { redirect, type RequestHandler } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';

/** Identisch zu src/lib/server/sso-crypto.ts auf der Playindex-Seite. */
async function signaturErzeugen(secret: string, timestamp: string, nonce: string, body: string) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    new Uint8Array(enc.encode(secret)),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new Uint8Array(enc.encode(`${timestamp}.${nonce}.${body}`))
  );
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export const GET: RequestHandler = async ({ url, locals }) => {
  // `locals.user` ist hier die BESTEHENDE Session der Partner-App.
  const nutzer = locals.user;
  if (!nutzer) {
    redirect(303, `/login?weiter=${encodeURIComponent(url.pathname + url.search)}`);
  }

  const koerper = JSON.stringify({
    external_user_id: nutzer.id,
    email: nutzer.email,
    redirect_to: url.searchParams.get('ziel') ?? '/buchen/sportcenter-hahn'
  });

  const timestamp = String(Math.floor(Date.now() / 1000));
  const nonce = crypto.randomUUID();
  const signatur = await signaturErzeugen(
    env.PLAYINDEX_PARTNER_SECRET,
    timestamp,
    nonce,
    koerper
  );

  const antwort = await fetch(`${env.PLAYINDEX_BASE_URL}/api/sso/ticket`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-playindex-partner': env.PLAYINDEX_PARTNER_NAME,
      'x-playindex-timestamp': timestamp,
      'x-playindex-nonce': nonce,
      'x-playindex-signature': `sha256=${signatur}`
    },
    body: koerper
  });

  if (!antwort.ok) {
    // Kein Handoff moeglich -> normaler Login auf Playindex, statt Fehlerseite.
    redirect(303, `${env.PLAYINDEX_BASE_URL}/login`);
  }

  const { url: handoffUrl } = (await antwort.json()) as { url: string };
  redirect(303, handoffUrl);
};
