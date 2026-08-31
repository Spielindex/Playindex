/**
 * Tests fuer die reinen SSO-Funktionen.
 *
 *   npm run test:sso
 *
 * Laeuft direkt auf Node (>= 22) ueber --experimental-strip-types, ohne
 * Testrunner - die Funktionen haben absichtlich keine Abhaengigkeiten.
 */
import assert from 'node:assert/strict';
import {
  MAX_SKEW,
  signaturErzeugen,
  signaturPruefen,
  zeitstempelGueltig,
  zielPruefen
} from './sso-crypto.ts';

let bestanden = 0;
const fehler: string[] = [];

async function pruefe(name: string, fn: () => void | Promise<void>) {
  try {
    await fn();
    bestanden++;
    console.log(`  [OK]   ${name}`);
  } catch (e) {
    fehler.push(name);
    console.log(`  [FAIL] ${name} -> ${(e as Error).message}`);
  }
}

const SECRET = 'partner-secret-tennisindex';
const BODY = JSON.stringify({ external_user_id: 'tx-1', email: 'bea@example.com' });
const TS = '1756600000';
const NONCE = 'nonce-1';

console.log('\n=== HMAC-Signatur ===');

await pruefe('gueltige Signatur wird akzeptiert', async () => {
  const sig = await signaturErzeugen({ secret: SECRET, timestamp: TS, nonce: NONCE, rawBody: BODY });
  assert.equal(
    await signaturPruefen({ secret: SECRET, timestamp: TS, nonce: NONCE, rawBody: BODY, signature: sig }),
    true
  );
});

await pruefe('Praefix "sha256=" wird akzeptiert', async () => {
  const sig = await signaturErzeugen({ secret: SECRET, timestamp: TS, nonce: NONCE, rawBody: BODY });
  assert.equal(
    await signaturPruefen({
      secret: SECRET, timestamp: TS, nonce: NONCE, rawBody: BODY, signature: `sha256=${sig}`
    }),
    true
  );
});

await pruefe('manipulierter Body faellt durch', async () => {
  const sig = await signaturErzeugen({ secret: SECRET, timestamp: TS, nonce: NONCE, rawBody: BODY });
  const boese = JSON.stringify({ external_user_id: 'tx-1', email: 'angreifer@example.com' });
  assert.equal(
    await signaturPruefen({ secret: SECRET, timestamp: TS, nonce: NONCE, rawBody: boese, signature: sig }),
    false
  );
});

await pruefe('fremdes Secret faellt durch', async () => {
  const sig = await signaturErzeugen({ secret: SECRET, timestamp: TS, nonce: NONCE, rawBody: BODY });
  assert.equal(
    await signaturPruefen({
      secret: 'anderes-secret', timestamp: TS, nonce: NONCE, rawBody: BODY, signature: sig
    }),
    false
  );
});

await pruefe('Signatur ist an Zeitstempel und Nonce gebunden', async () => {
  const sig = await signaturErzeugen({ secret: SECRET, timestamp: TS, nonce: NONCE, rawBody: BODY });
  assert.equal(
    await signaturPruefen({ secret: SECRET, timestamp: '1756600001', nonce: NONCE, rawBody: BODY, signature: sig }),
    false
  );
  assert.equal(
    await signaturPruefen({ secret: SECRET, timestamp: TS, nonce: 'nonce-2', rawBody: BODY, signature: sig }),
    false
  );
});

await pruefe('Schrott-Signaturen werfen nicht, sondern liefern false', async () => {
  for (const s of ['', 'nichthex', 'abc', 'sha256=', 'ZZ']) {
    assert.equal(
      await signaturPruefen({ secret: SECRET, timestamp: TS, nonce: NONCE, rawBody: BODY, signature: s }),
      false,
      `Signatur ${JSON.stringify(s)}`
    );
  }
});

console.log('\n=== Zeitstempel ===');

await pruefe('frischer Zeitstempel gilt', () => {
  const jetzt = Date.now();
  assert.equal(zeitstempelGueltig(String(Math.floor(jetzt / 1000)), jetzt), true);
});

await pruefe('zu alter und zu neuer Zeitstempel gilt nicht', () => {
  const jetzt = Date.now();
  const sek = Math.floor(jetzt / 1000);
  assert.equal(zeitstempelGueltig(String(sek - MAX_SKEW - 1), jetzt), false);
  assert.equal(zeitstempelGueltig(String(sek + MAX_SKEW + 1), jetzt), false);
});

await pruefe('Unsinn im Zeitstempel gilt nicht', () => {
  for (const t of ['', '   ', 'abc', 'NaN', 'Infinity']) {
    assert.equal(zeitstempelGueltig(t), false, `Zeitstempel ${JSON.stringify(t)}`);
  }
});

console.log('\n=== Open-Redirect-Schutz ===');

const ERLAUBT = ['/buchen', '/match', '/meine-buchungen'];
const FALLBACK = '/';

await pruefe('erlaubte relative Pfade kommen durch', () => {
  assert.equal(zielPruefen('/buchen/sportcenter-hahn', ERLAUBT, FALLBACK), '/buchen/sportcenter-hahn');
  assert.equal(zielPruefen('/buchen?datum=2026-09-08', ERLAUBT, FALLBACK), '/buchen?datum=2026-09-08');
  assert.equal(zielPruefen('/meine-buchungen', ERLAUBT, FALLBACK), '/meine-buchungen');
});

await pruefe('fremde Ziele werden abgewiesen', () => {
  const boese = [
    'https://evil.com',
    '//evil.com',
    '/\\evil.com',
    'http://playindex.de.evil.com',
    'javascript:alert(1)',
    '/buchen\n/Set-Cookie: x=1',
    '/buchen/../../admin',
    '/admin',
    '/buchenX'
  ];
  for (const z of boese) {
    assert.equal(zielPruefen(z, ERLAUBT, FALLBACK), FALLBACK, `Ziel ${JSON.stringify(z)}`);
  }
});

await pruefe('leeres Ziel faellt auf den Fallback', () => {
  assert.equal(zielPruefen(null, ERLAUBT, FALLBACK), FALLBACK);
  assert.equal(zielPruefen(undefined, ERLAUBT, FALLBACK), FALLBACK);
  assert.equal(zielPruefen('', ERLAUBT, FALLBACK), FALLBACK);
});

console.log(`\nbestanden: ${bestanden}, fehlgeschlagen: ${fehler.length}`);
if (fehler.length > 0) process.exit(1);
