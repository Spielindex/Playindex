import { env } from '$env/dynamic/private';
import { zielPruefen } from './sso-crypto';

export { signaturPruefen, signaturErzeugen, zeitstempelGueltig } from './sso-crypto';

/**
 * Ein eigenes HMAC-Secret je Partnerdomain. Getrennte Secrets bedeuten:
 * ein kompromittierter Partner kann nur seine eigenen Nutzer behaupten,
 * nicht das ganze System uebernehmen.
 */
function partnerSecrets(): Record<string, string> {
  const roh = env.SSO_PARTNER_SECRETS;
  if (!roh) return {};
  try {
    const geparst: unknown = JSON.parse(roh);
    if (!geparst || typeof geparst !== 'object') return {};
    return geparst as Record<string, string>;
  } catch {
    return {};
  }
}

export function partnerSecret(quelle: string): string | null {
  const secret = partnerSecrets()[quelle];
  return typeof secret === 'string' && secret.length > 0 ? secret : null;
}

function erlaubtePraefixe(): string[] {
  return (env.SSO_ALLOWED_REDIRECT_PREFIXES ?? '/buchen,/match,/meine-buchungen,/profil')
    .split(',')
    .map((p) => p.trim())
    .filter(Boolean);
}

/** Open-Redirect-Schutz. Faellt bei allem Unklaren auf `fallback` zurueck. */
export function sicheresZiel(ziel: string | null | undefined, fallback = '/'): string {
  return zielPruefen(ziel, erlaubtePraefixe(), fallback);
}
