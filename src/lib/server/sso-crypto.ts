/**
 * Reine Funktionen fuer die SSO-Bruecke - ohne Env, ohne Supabase, ohne
 * SvelteKit. Genau deshalb direkt testbar (siehe src/lib/server/sso.test.ts).
 */

const encoder = new TextEncoder();

function hexZuBytes(hex: string): Uint8Array<ArrayBuffer> | null {
  if (hex.length === 0 || hex.length % 2 !== 0 || !/^[0-9a-f]*$/i.test(hex)) return null;
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

/**
 * TextEncoder liefert `Uint8Array<ArrayBufferLike>`; Web Crypto verlangt eine
 * `BufferSource` ueber einem echten ArrayBuffer. Die Kopie loest das sauber,
 * statt den Typ wegzucasten.
 */
function nachricht(timestamp: string, nonce: string, rawBody: string): Uint8Array<ArrayBuffer> {
  return new Uint8Array(encoder.encode(`${timestamp}.${nonce}.${rawBody}`));
}

function secretBytes(secret: string): Uint8Array<ArrayBuffer> {
  return new Uint8Array(encoder.encode(secret));
}

async function schluessel(secret: string, zweck: 'sign' | 'verify'): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    secretBytes(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    [zweck]
  );
}

/**
 * Prueft die Signatur eines Partner-Requests.
 *
 * Signiert wird `${timestamp}.${nonce}.${rawBody}`: der Zeitstempel bindet die
 * Signatur an ein Zeitfenster, die Nonce an genau einen Request, der Body an
 * genau diesen Inhalt. Die Pruefung laeuft ueber crypto.subtle.verify und ist
 * damit laufzeitkonstant - kein String-Vergleich, kein Timing-Leak.
 *
 * Web Crypto ist auf Cloudflare Workers nativ verfuegbar, keine Node-Polyfills.
 */
export async function signaturPruefen(opts: {
  secret: string;
  timestamp: string;
  nonce: string;
  rawBody: string;
  signature: string;
}): Promise<boolean> {
  const signatur = hexZuBytes(opts.signature.replace(/^sha256=/, ''));
  if (!signatur) return false;

  return crypto.subtle.verify(
    'HMAC',
    await schluessel(opts.secret, 'verify'),
    signatur,
    nachricht(opts.timestamp, opts.nonce, opts.rawBody)
  );
}

/** Gegenstueck fuer die Partnerseite (siehe examples/partner/). */
export async function signaturErzeugen(opts: {
  secret: string;
  timestamp: string;
  nonce: string;
  rawBody: string;
}): Promise<string> {
  const sig = await crypto.subtle.sign(
    'HMAC',
    await schluessel(opts.secret, 'sign'),
    nachricht(opts.timestamp, opts.nonce, opts.rawBody)
  );
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Maximale Abweichung des Zeitstempels in Sekunden. */
export const MAX_SKEW = 60;

export function zeitstempelGueltig(timestamp: string, jetzt = Date.now()): boolean {
  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || timestamp.trim() === '') return false;
  return Math.abs(jetzt / 1000 - ts) <= MAX_SKEW;
}

/**
 * Laesst ausschliesslich relative Pfade der eigenen Seite durch.
 *
 * Abgewiesen werden: absolute URLs, protokollrelative URLs (`//evil.com`),
 * Backslash-Varianten (`/\evil.com` - von einigen Browsern wie `//` behandelt),
 * eingebettete Zeilenumbrueche (Header-Injection) und alles ausserhalb der
 * Allowlist.
 */
export function zielPruefen(
  ziel: string | null | undefined,
  erlaubtePraefixe: string[],
  fallback: string
): string {
  if (!ziel) return fallback;
  if (!ziel.startsWith('/')) return fallback;
  if (ziel.startsWith('//') || ziel.startsWith('/\\')) return fallback;
  if (/[\r\n\t\0]/.test(ziel)) return fallback;

  const pfad = ziel.split('?')[0].split('#')[0];
  if (pfad.includes('..')) return fallback;

  return erlaubtePraefixe.some((p) => pfad === p || pfad.startsWith(`${p}/`)) ? ziel : fallback;
}
