/**
 * Zeitzonen-Helfer fuer das Buchungsgrid.
 *
 * Das Problem: Buchungen kommen als UTC-Instants, Oeffnungszeiten als lokale
 * Wandzeit ("07:00"), und der Browser des Spielers steht irgendwo. Gerendert
 * werden muss immer die Wandzeit des Clubs - sonst zeigt das Grid einem Nutzer
 * im Urlaub die falschen Slots.
 *
 * Bewusst ohne date-fns-tz o.ae.: Intl reicht, und jedes KB zaehlt auf Mobile.
 */

/** Offset der Zone gegenueber UTC zu diesem Instant, in Millisekunden. */
export function zonenOffsetMs(instant: Date, zone: string): number {
  const teile = new Intl.DateTimeFormat('en-US', {
    timeZone: zone,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  }).formatToParts(instant);

  const hole = (typ: string) => Number(teile.find((t) => t.type === typ)?.value ?? '0');

  const alsUtc = Date.UTC(
    hole('year'),
    hole('month') - 1,
    hole('day'),
    // Manche ICU-Versionen liefern "24" statt "00" fuer Mitternacht.
    hole('hour') % 24,
    hole('minute'),
    hole('second')
  );

  return alsUtc - instant.getTime();
}

/**
 * Wandelt lokale Wandzeit des Clubs in einen echten Instant.
 *
 * Zwei Durchlaeufe, weil der Offset selbst vom Ergebnis abhaengt: an
 * Zeitumstellungstagen liegt der erste Schaetzwert sonst eine Stunde daneben.
 */
export function wandzeitZuInstant(datum: string, zeit: string, zone: string): Date {
  const naiv = Date.parse(`${datum}T${zeit.slice(0, 5)}:00Z`);
  const ersterOffset = zonenOffsetMs(new Date(naiv), zone);
  const zweiterOffset = zonenOffsetMs(new Date(naiv - ersterOffset), zone);
  return new Date(naiv - zweiterOffset);
}

/** Wandzeit des Clubs zu einem Instant, als { datum: 'YYYY-MM-DD', zeit: 'HH:MM' }. */
export function instantZuWandzeit(instant: Date, zone: string): { datum: string; zeit: string } {
  const verschoben = new Date(instant.getTime() + zonenOffsetMs(instant, zone));
  return {
    datum: verschoben.toISOString().slice(0, 10),
    zeit: verschoben.toISOString().slice(11, 16)
  };
}

export function uhrzeit(instant: Date | string, zone: string): string {
  const d = typeof instant === 'string' ? new Date(instant) : instant;
  return instantZuWandzeit(d, zone).zeit;
}

/** "07:00:00" oder "07:00" -> Minuten seit Mitternacht. "24:00" -> 1440. */
export function zeitTextZuMinuten(text: string): number {
  const [h, m] = text.split(':').map(Number);
  return h * 60 + (m || 0);
}

export function minutenZuZeitText(minuten: number): string {
  const h = Math.floor(minuten / 60);
  const m = minuten % 60;
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

export type Slot = {
  /** Minuten seit Mitternacht, lokale Wandzeit des Clubs */
  minute: number;
  label: string;
  start: Date;
  ende: Date;
};

/**
 * Gibt es diese Wandzeit an diesem Tag ueberhaupt?
 *
 * In der Nacht der Umstellung auf Sommerzeit springt die Uhr von 02:00 auf
 * 03:00 - 02:00 und 02:30 existieren schlicht nicht. Ohne diese Pruefung
 * landen sie auf demselben Instant wie 03:00/03:30 und das Grid zeigt
 * Dubletten, die sich gegenseitig als belegt markieren.
 */
export function wandzeitExistiert(datum: string, zeit: string, zone: string): boolean {
  const instant = wandzeitZuInstant(datum, zeit, zone);
  const zurueck = instantZuWandzeit(instant, zone);
  return zurueck.datum === datum && zurueck.zeit === zeit.slice(0, 5);
}

/**
 * Erzeugt die Zeitachse des Grids.
 *
 * Rechnet in lokalen Wandzeit-Minuten und wandelt jeden Slot einzeln in einen
 * Instant. Nicht existierende Wandzeiten (Umstellung auf Sommerzeit) fallen
 * raus - der Tag hat dann korrekt eine Stunde weniger Slots.
 *
 * Der umgekehrte Fall (Umstellung auf Winterzeit, 02:00-03:00 gibt es zweimal)
 * wird bewusst nicht aufgeteilt: die Achse zeigt die erste Stunde. Bei
 * Oeffnungszeiten ab 07:00 tritt der Fall ohnehin nie auf, und die Wahrheit
 * ueber Doppelbelegung steht am Ende im EXCLUDE-Constraint der Datenbank.
 */
export function slotsErzeugen(
  datum: string,
  vonMinute: number,
  bisMinute: number,
  schrittMinuten: number,
  zone: string
): Slot[] {
  const slots: Slot[] = [];
  for (let m = vonMinute; m + schrittMinuten <= bisMinute; m += schrittMinuten) {
    const label = minutenZuZeitText(m);
    if (m < 24 * 60 && !wandzeitExistiert(datum, label, zone)) continue;
    slots.push({
      minute: m,
      label,
      start: wandzeitZuInstant(datum, label, zone),
      ende: wandzeitZuInstant(datum, minutenZuZeitText(m + schrittMinuten), zone)
    });
  }
  return slots;
}

export type Zeitraum = { starts_at: string; ends_at: string };

/** Erste Belegung, die sich mit [start, ende) ueberschneidet - sonst null. */
export function belegungFinden<T extends Zeitraum>(
  start: Date,
  ende: Date,
  belegungen: readonly T[]
): T | null {
  const a = start.getTime();
  const b = ende.getTime();
  for (const belegung of belegungen) {
    if (Date.parse(belegung.starts_at) < b && Date.parse(belegung.ends_at) > a) return belegung;
  }
  return null;
}

/**
 * Wie lange kann ab `abSlot` am Stueck gebucht werden?
 *
 * Begrenzt durch die naechste Belegung, das Ende der Oeffnungszeit und die
 * Maximaldauer des Clubs. Ergebnis ist immer ein Vielfaches des Rasters.
 */
export function maximaleDauerMinuten(
  abIndex: number,
  slots: readonly Slot[],
  belegungen: readonly Zeitraum[],
  schrittMinuten: number,
  maxMinuten: number
): number {
  let dauer = 0;
  for (let i = abIndex; i < slots.length && dauer < maxMinuten; i++) {
    if (belegungFinden(slots[i].start, slots[i].ende, belegungen)) break;
    // Luecke in der Achse (z. B. anderer Platz, andere Oeffnungszeit)
    if (i > abIndex && slots[i].minute !== slots[i - 1].minute + schrittMinuten) break;
    dauer += schrittMinuten;
  }
  return Math.min(dauer, maxMinuten);
}

/** Mögliche Buchungsdauern ab einem Slot, in Minuten. */
export function dauerOptionen(min: number, max: number, schritt: number): number[] {
  const optionen: number[] = [];
  for (let d = min; d <= max; d += schritt) optionen.push(d);
  return optionen;
}
