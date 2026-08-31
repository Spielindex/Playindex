/**
 * Tests fuer die Zeitzonen-Logik des Grids.
 *
 *   npm run test:zeit
 *
 * Schwerpunkt: Sommer-/Winterzeit. Genau da geht so ein Grid kaputt, und genau
 * das faellt im Alltag erst am Umstellungswochenende auf.
 */
import assert from 'node:assert/strict';
import {
  belegungFinden,
  instantZuWandzeit,
  maximaleDauerMinuten,
  slotsErzeugen,
  uhrzeit,
  wandzeitZuInstant,
  zeitTextZuMinuten,
  zonenOffsetMs
} from './zeit.ts';

const ZONE = 'Europe/Berlin';
let bestanden = 0;
const fehler: string[] = [];

function pruefe(name: string, fn: () => void) {
  try {
    fn();
    bestanden++;
    console.log(`  [OK]   ${name}`);
  } catch (e) {
    fehler.push(name);
    console.log(`  [FAIL] ${name} -> ${(e as Error).message}`);
  }
}

console.log('\n=== Wandzeit -> Instant ===');

pruefe('Sommerzeit: 08.09.2026 16:00 Berlin = 14:00 UTC', () => {
  assert.equal(wandzeitZuInstant('2026-09-08', '16:00', ZONE).toISOString(), '2026-09-08T14:00:00.000Z');
});

pruefe('Winterzeit: 08.01.2026 16:00 Berlin = 15:00 UTC', () => {
  assert.equal(wandzeitZuInstant('2026-01-08', '16:00', ZONE).toISOString(), '2026-01-08T15:00:00.000Z');
});

pruefe('Offset kippt zur Zeitumstellung (29.03.2026)', () => {
  // 01:30 Berlin ist noch CET (+1), 03:30 schon CEST (+2)
  assert.equal(wandzeitZuInstant('2026-03-29', '01:30', ZONE).toISOString(), '2026-03-29T00:30:00.000Z');
  assert.equal(wandzeitZuInstant('2026-03-29', '03:30', ZONE).toISOString(), '2026-03-29T01:30:00.000Z');
});

pruefe('Offset kippt zurueck (25.10.2026)', () => {
  assert.equal(zonenOffsetMs(new Date('2026-10-25T00:00:00Z'), ZONE), 2 * 3600_000);
  assert.equal(zonenOffsetMs(new Date('2026-10-25T02:00:00Z'), ZONE), 1 * 3600_000);
});

pruefe('Rueckrichtung ist konsistent', () => {
  for (const [datum, zeit] of [
    ['2026-09-08', '07:00'],
    ['2026-01-08', '22:30'],
    ['2026-03-29', '05:00'],
    ['2026-10-25', '05:00']
  ]) {
    const instant = wandzeitZuInstant(datum, zeit, ZONE);
    assert.deepEqual(instantZuWandzeit(instant, ZONE), { datum, zeit }, `${datum} ${zeit}`);
  }
});

pruefe('uhrzeit() rendert Clubzeit, nicht Browserzeit', () => {
  assert.equal(uhrzeit('2026-09-08T14:00:00Z', ZONE), '16:00');
  assert.equal(uhrzeit('2026-09-08T14:00:00Z', 'UTC'), '14:00');
  assert.equal(uhrzeit('2026-09-08T14:00:00Z', 'America/New_York'), '10:00');
});

console.log('\n=== Zeitachse ===');

pruefe('07:00-23:00 im 30-Minuten-Raster gibt 32 Slots', () => {
  const slots = slotsErzeugen('2026-09-08', 7 * 60, 23 * 60, 30, ZONE);
  assert.equal(slots.length, 32);
  assert.equal(slots[0].label, '07:00');
  assert.equal(slots.at(-1)?.label, '22:30');
});

pruefe('Umstellung auf Sommerzeit laesst 02:00 und 02:30 verschwinden', () => {
  // 29.03.2026: die Uhr springt von 02:00 auf 03:00. Diese Wandzeiten
  // existieren nicht und duerfen nicht im Grid stehen.
  const slots = slotsErzeugen('2026-03-29', 0, 4 * 60, 30, ZONE);
  assert.deepEqual(
    slots.map((s) => s.label),
    ['00:00', '00:30', '01:00', '01:30', '03:00', '03:30']
  );
  // Kein Slot darf auf demselben Instant liegen wie ein anderer
  assert.equal(new Set(slots.map((s) => s.start.getTime())).size, slots.length);
});

pruefe('normaler Tag verliert keine Slots', () => {
  const slots = slotsErzeugen('2026-09-08', 0, 4 * 60, 30, ZONE);
  assert.equal(slots.length, 8);
  assert.equal(new Set(slots.map((s) => s.start.getTime())).size, 8);
});

pruefe('Umstellung auf Winterzeit erzeugt keine Dubletten', () => {
  const slots = slotsErzeugen('2026-10-25', 0, 4 * 60, 30, ZONE);
  assert.equal(new Set(slots.map((s) => s.start.getTime())).size, slots.length);
});

pruefe('Slot bis 24:00 wird korrekt aufgeloest', () => {
  const slots = slotsErzeugen('2026-09-08', 23 * 60, 24 * 60, 30, ZONE);
  assert.equal(slots.length, 2);
  assert.equal(slots.at(-1)?.ende.toISOString(), '2026-09-08T22:00:00.000Z');
});

console.log('\n=== Belegung ===');

const BELEGUNGEN = [
  { starts_at: '2026-09-08T14:00:00Z', ends_at: '2026-09-08T16:00:00Z' } // 16-18 Berlin
];

pruefe('Ueberschneidung wird erkannt', () => {
  const treffer = (von: string, bis: string) =>
    belegungFinden(new Date(von), new Date(bis), BELEGUNGEN) !== null;

  assert.equal(treffer('2026-09-08T14:00:00Z', '2026-09-08T14:30:00Z'), true, 'exakt am Anfang');
  assert.equal(treffer('2026-09-08T15:30:00Z', '2026-09-08T16:00:00Z'), true, 'letzter Slot');
  assert.equal(treffer('2026-09-08T13:30:00Z', '2026-09-08T14:00:00Z'), false, 'direkt davor');
  assert.equal(treffer('2026-09-08T16:00:00Z', '2026-09-08T16:30:00Z'), false, 'direkt danach');
  assert.equal(treffer('2026-09-08T13:45:00Z', '2026-09-08T14:15:00Z'), true, 'ragt hinein');
});

console.log('\n=== Maximale Buchungsdauer ===');

const SLOTS = slotsErzeugen('2026-09-08', 7 * 60, 23 * 60, 30, ZONE);

pruefe('freier Platz: begrenzt durch Maximaldauer des Clubs', () => {
  assert.equal(maximaleDauerMinuten(0, SLOTS, [], 30, 180), 180);
});

pruefe('Belegung kappt die Dauer', () => {
  // Slot 18 = 16:00 Berlin, Belegung ab 16:00 -> 0 Minuten frei
  const index16 = SLOTS.findIndex((s) => s.label === '16:00');
  assert.equal(maximaleDauerMinuten(index16, SLOTS, BELEGUNGEN, 30, 180), 0);
  // ab 15:00 sind es genau 60 Minuten bis zur Belegung
  const index15 = SLOTS.findIndex((s) => s.label === '15:00');
  assert.equal(maximaleDauerMinuten(index15, SLOTS, BELEGUNGEN, 30, 180), 60);
});

pruefe('Ende der Oeffnungszeit kappt die Dauer', () => {
  const index2200 = SLOTS.findIndex((s) => s.label === '22:00');
  assert.equal(maximaleDauerMinuten(index2200, SLOTS, [], 30, 180), 60);
});

console.log('\n=== Kleinkram ===');

pruefe('Zeittexte werden geparst', () => {
  assert.equal(zeitTextZuMinuten('07:00:00'), 420);
  assert.equal(zeitTextZuMinuten('24:00'), 1440);
  assert.equal(zeitTextZuMinuten('00:30'), 30);
});

console.log(`\nbestanden: ${bestanden}, fehlgeschlagen: ${fehler.length}`);
if (fehler.length > 0) process.exit(1);
