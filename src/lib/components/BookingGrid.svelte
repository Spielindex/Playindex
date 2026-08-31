<script lang="ts">
  import type { DaySchedule, ScheduleCourt } from '$lib/types/database';
  import {
    belegungFinden,
    instantZuWandzeit,
    maximaleDauerMinuten,
    slotsErzeugen,
    zeitTextZuMinuten,
    type Slot
  } from '$lib/utils/zeit';

  type Auswahl = {
    court: ScheduleCourt;
    slot: Slot;
    maxDauer: number;
  };

  let {
    plan,
    datum,
    jetzt = new Date(),
    onauswahl
  }: {
    plan: DaySchedule;
    datum: string;
    jetzt?: Date;
    onauswahl: (auswahl: Auswahl) => void;
  } = $props();

  const zone = $derived(plan.club.timezone);
  const schritt = $derived(plan.club.slot_minutes);

  /**
   * Achse spannt vom fruehesten Oeffnen bis zum spaetesten Schliessen.
   *
   * Am heutigen Tag faellt alles weg, was schon vorbei ist: wer abends um
   * 20 Uhr die App oeffnet, soll nicht erst durch zwoelf tote Stunden
   * scrollen. Bleiben dadurch weniger als zwei Slots uebrig, zeigen wir
   * lieber den ganzen Tag als ein leeres Grid.
   */
  const fenster = $derived.by(() => {
    const offen = plan.courts.filter((c) => c.opens_at && c.closes_at);
    if (offen.length === 0) return null;

    const oeffnet = Math.min(...offen.map((c) => zeitTextZuMinuten(c.opens_at!)));
    const schliesst = Math.max(...offen.map((c) => zeitTextZuMinuten(c.closes_at!)));

    const heute = instantZuWandzeit(jetzt, zone);
    if (heute.datum !== datum) return { von: oeffnet, bis: schliesst };

    const jetztMinute = zeitTextZuMinuten(heute.zeit);
    const abJetzt = Math.floor(jetztMinute / schritt) * schritt;
    const von = Math.max(oeffnet, abJetzt);

    return schliesst - von >= 2 * schritt
      ? { von, bis: schliesst }
      : { von: oeffnet, bis: schliesst };
  });

  const slots = $derived(
    fenster ? slotsErzeugen(datum, fenster.von, fenster.bis, schritt, zone) : []
  );

  type ZellStatus = 'frei' | 'belegt' | 'match' | 'meine' | 'zu' | 'vorbei';

  function status(court: ScheduleCourt, slot: Slot): ZellStatus {
    if (!court.opens_at || !court.closes_at) return 'zu';
    if (
      slot.minute < zeitTextZuMinuten(court.opens_at) ||
      slot.minute + schritt > zeitTextZuMinuten(court.closes_at)
    ) {
      return 'zu';
    }

    const belegung = belegungFinden(slot.start, slot.ende, court.bookings);
    if (belegung) {
      if (belegung.is_mine) return 'meine';
      return belegung.is_open_match ? 'match' : 'belegt';
    }

    return slot.ende <= jetzt ? 'vorbei' : 'frei';
  }

  function zellKlasse(s: ZellStatus): string {
    switch (s) {
      case 'frei':
        return 'bg-free text-free-foreground hover:brightness-95 active:scale-[0.97] cursor-pointer';
      case 'match':
        return 'bg-match/30 text-match-foreground cursor-pointer hover:brightness-95';
      case 'meine':
        return 'bg-primary text-primary-foreground';
      case 'belegt':
        return 'bg-busy text-muted-foreground/70';
      case 'vorbei':
        return 'bg-transparent text-muted-foreground/30';
      case 'zu':
        return 'bg-transparent';
    }
  }

  function beschriftung(s: ZellStatus, court: ScheduleCourt, slot: Slot): string {
    if (s === 'match') {
      const b = belegungFinden(slot.start, slot.ende, court.bookings);
      return b?.players_needed ? `sucht ${b.players_needed}` : 'offen';
    }
    if (s === 'meine') return 'du';
    return '';
  }

  function tippen(court: ScheduleCourt, slot: Slot, index: number) {
    const s = status(court, slot);
    if (s !== 'frei') return;

    const bisSchliessung = zeitTextZuMinuten(court.closes_at!) - slot.minute;
    const maxDauer = Math.min(
      maximaleDauerMinuten(
        index,
        slots,
        court.bookings,
        schritt,
        plan.club.max_duration_minutes
      ),
      bisSchliessung
    );

    if (maxDauer < plan.club.min_duration_minutes) return;
    onauswahl({ court, slot, maxDauer });
  }

  /** Position der "Jetzt"-Linie in Prozent - nur wenn heute angezeigt wird. */
  const jetztPosition = $derived.by(() => {
    if (slots.length === 0) return null;
    const erste = slots[0].start.getTime();
    const letzte = slots.at(-1)!.ende.getTime();
    const t = jetzt.getTime();
    if (t < erste || t > letzte) return null;
    return ((t - erste) / (letzte - erste)) * 100;
  });

  const ZEILE = 44;      // px je Slot-Zeile, auch Basis fuer die Jetzt-Linie
  const ZEITSPALTE = 56; // muss zu w-14 und scroll-padding-left passen
  const SPALTE = 104;    // muss zu w-[104px] passen
</script>

{#if !fenster}
  <div class="rounded-2xl border border-dashed border-border p-10 text-center">
    <p class="text-sm text-muted-foreground">An diesem Tag ist geschlossen.</p>
  </div>
{:else}
  <div class="rounded-2xl border border-border bg-card">
    <!--
      Horizontaler Scroll: die Zeitspalte bleibt per position:sticky stehen,
      die Platzspalten wandern darunter durch. scroll-snap laesst sie sauber
      einrasten, damit man auf dem Handy nicht zwischen zwei Plaetzen haengt.

      scroll-padding-left ist dabei nicht optional: ohne es richtet snap die
      Spalte am Scrollport-Rand aus - und damit exakt hinter der klebenden
      Zeitspalte, die dort sitzt. Der Wert muss deren Breite entsprechen.

      max-h + overflow-auto sind ebenfalls noetig: `sticky top-0` klebt am
      naechsten Scrollport. Ohne eigene Hoehe scrollt die Seite statt des
      Containers - und die Platznamen waeren beim Runterscrollen weg.
    -->
    <div
      class="relative max-h-[70dvh] overflow-auto overscroll-x-contain [scrollbar-width:thin]"
      style="scroll-snap-type: x proximity; scroll-padding-left: {ZEITSPALTE}px;"
      role="group"
      aria-label="Platzbelegung"
    >
      <!--
        w-max statt min-w-max: sonst dehnt sich der Inhalt auf die volle
        Containerbreite und die Jetzt-Linie laeuft auf grossen Bildschirmen
        rechts ins Leere.
      -->
      <div class="w-max">
        <!-- Kopfzeile -->
        <div class="sticky top-0 z-20 flex border-b border-border bg-card/95 backdrop-blur">
          <div class="sticky left-0 z-30 w-14 shrink-0 bg-card/95"></div>
          {#each plan.courts as court (court.id)}
            <div
              class="w-[104px] shrink-0 px-1 py-2 text-center"
              style="scroll-snap-align: start;"
            >
              <p class="truncate text-sm font-medium">{court.name}</p>
              <p class="text-[11px] text-muted-foreground">
                {court.is_indoor ? 'Halle' : 'Außen'}
              </p>
            </div>
          {/each}
        </div>

        <!-- Raster -->
        <div class="relative">
          {#if jetztPosition !== null}
            <!--
              z-20, damit das Label nicht hinter der klebenden Zeitspalte (z-10)
              verschwindet; das Label selbst klebt mit, sonst waere es beim
              horizontalen Scrollen weg.
            -->
            <div
              class="pointer-events-none absolute inset-x-0 z-20 h-0"
              style="top: {(jetztPosition / 100) * (slots.length * ZEILE)}px;"
              aria-hidden="true"
            >
              <div class="absolute inset-x-0 top-0 border-t-2 border-destructive/70"></div>
              <span
                class="sticky left-2 inline-block -translate-y-1/2 rounded-full bg-destructive
                       px-1.5 py-px text-[10px] font-medium leading-tight text-white"
              >
                jetzt
              </span>
            </div>
          {/if}

          {#each slots as slot, i (slot.minute)}
            <div class="flex" style="height: {ZEILE}px;">
              <div
                class="sticky left-0 z-10 flex w-14 shrink-0 items-start justify-end
                       bg-card pr-2 pt-1 text-[11px] tabular-nums text-muted-foreground"
              >
                {slot.minute % 60 === 0 ? slot.label : ''}
              </div>

              {#each plan.courts as court (court.id)}
                {@const s = status(court, slot)}
                <div class="w-[104px] shrink-0 px-1 py-0.5" style="scroll-snap-align: start;">
                  {#if s === 'frei'}
                    <button
                      type="button"
                      onclick={() => tippen(court, slot, i)}
                      class="h-full w-full rounded-lg text-[11px] font-medium transition
                             {zellKlasse(s)}"
                      aria-label="{court.name}, {slot.label} Uhr, frei"
                    >
                      {slot.label}
                    </button>
                  {:else}
                    <div
                      class="flex h-full w-full items-center justify-center rounded-lg
                             text-[11px] {zellKlasse(s)}"
                      aria-label="{court.name}, {slot.label} Uhr, {s === 'zu'
                        ? 'geschlossen'
                        : s === 'vorbei'
                          ? 'vergangen'
                          : 'belegt'}"
                    >
                      {beschriftung(s, court, slot)}
                    </div>
                  {/if}
                </div>
              {/each}
            </div>
          {/each}
        </div>
      </div>
    </div>
  </div>

  <div class="mt-3 flex flex-wrap gap-x-4 gap-y-1 px-1 text-[11px] text-muted-foreground">
    <span class="flex items-center gap-1.5">
      <span class="size-2.5 rounded-sm bg-free"></span> frei
    </span>
    <span class="flex items-center gap-1.5">
      <span class="size-2.5 rounded-sm bg-busy"></span> belegt
    </span>
    <span class="flex items-center gap-1.5">
      <span class="size-2.5 rounded-sm bg-match/60"></span> offenes Match
    </span>
    <span class="flex items-center gap-1.5">
      <span class="size-2.5 rounded-sm bg-primary"></span> deine Buchung
    </span>
  </div>
{/if}
