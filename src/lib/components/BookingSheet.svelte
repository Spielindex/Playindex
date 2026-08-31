<script lang="ts">
  import { enhance } from '$app/forms';
  import type { DaySchedule, ScheduleCourt } from '$lib/types/database';
  import { dauerOptionen, minutenZuZeitText, type Slot } from '$lib/utils/zeit';

  let {
    plan,
    auswahl,
    angemeldet,
    preisAbfrage,
    onschliessen
  }: {
    plan: DaySchedule;
    auswahl: { court: ScheduleCourt; slot: Slot; maxDauer: number } | null;
    angemeldet: boolean;
    preisAbfrage: (courtId: string, start: Date, ende: Date) => Promise<number | null>;
    onschliessen: () => void;
  } = $props();

  /**
   * `null` = noch nichts gewaehlt, dann gilt die Mindestdauer des Clubs.
   * Als $derived statt $state, damit die Dauer bei jeder neuen Auswahl
   * automatisch wieder passt, ohne den Startwert einzufrieren.
   */
  let dauerWahl = $state<number | null>(null);
  let offenesMatch = $state(false);
  let spielerGesucht = $state(1);
  let preisCent = $state<number | null>(null);
  let preisLaeuft = $state(false);
  let sendet = $state(false);

  const optionen = $derived(
    auswahl ? dauerOptionen(plan.club.min_duration_minutes, auswahl.maxDauer, plan.club.slot_minutes) : []
  );

  const dauer = $derived(
    dauerWahl ?? Math.min(plan.club.min_duration_minutes, auswahl?.maxDauer ?? 0)
  );

  const ende = $derived(
    auswahl ? new Date(auswahl.slot.start.getTime() + dauer * 60_000) : null
  );

  // Neue Auswahl -> zurueck zur Mindestdauer. Der Match-Toggle bleibt, weil er
  // eine Absicht des Spielers ist und nicht zum Slot gehoert.
  $effect(() => {
    auswahl;
    dauerWahl = null;
  });

  /**
   * Der Preis kommt immer vom Server (booking.price_for_me). Ihn im Client
   * nachzurechnen hiesse, die Tarifregeln zu duplizieren - und irgendwann
   * weichen die beiden Ergebnisse voneinander ab.
   */
  $effect(() => {
    if (!auswahl || !ende) return;
    const court = auswahl.court.id;
    const start = auswahl.slot.start;
    const bis = ende;
    preisLaeuft = true;
    let abgebrochen = false;
    preisAbfrage(court, start, bis).then((cent) => {
      if (!abgebrochen) {
        preisCent = cent;
        preisLaeuft = false;
      }
    });
    return () => {
      abgebrochen = true;
    };
  });

  const preisText = $derived(
    preisCent === null
      ? '—'
      : (preisCent / 100).toLocaleString('de-DE', {
          style: 'currency',
          currency: plan.club.currency
        })
  );

  function zeitspanne(): string {
    if (!auswahl || !ende) return '';
    const startMin = auswahl.slot.minute;
    return `${minutenZuZeitText(startMin)} – ${minutenZuZeitText(startMin + dauer)}`;
  }
</script>

<svelte:window
  onkeydown={(e: KeyboardEvent) => {
    if (auswahl && e.key === 'Escape') onschliessen();
  }}
/>

{#if auswahl}
  <!-- Backdrop -->
  <button
    type="button"
    class="fixed inset-0 z-40 bg-black/40 backdrop-blur-[2px]"
    onclick={onschliessen}
    aria-label="Schließen"
  ></button>

  <div
    class="fixed inset-x-0 bottom-0 z-50 rounded-t-3xl border-t border-border bg-card
           pb-[env(safe-area-inset-bottom)] shadow-2xl sm:inset-x-auto sm:bottom-auto
           sm:left-1/2 sm:top-1/2 sm:w-[420px] sm:-translate-x-1/2 sm:-translate-y-1/2
           sm:rounded-3xl sm:border"
    role="dialog"
    aria-modal="true"
    aria-labelledby="sheet-titel"
  >
    <div class="mx-auto mt-2 h-1 w-10 rounded-full bg-border sm:hidden"></div>

    <div class="px-5 pb-5 pt-4">
      <h2 id="sheet-titel" class="text-lg font-semibold tracking-tight">
        {auswahl.court.name}
      </h2>
      <p class="mt-0.5 text-sm text-muted-foreground">
        {new Intl.DateTimeFormat('de-DE', { weekday: 'long', day: 'numeric', month: 'long' }).format(
          new Date(`${plan.date}T12:00:00Z`)
        )} · {zeitspanne()}
      </p>

      <!-- Dauer -->
      <fieldset class="mt-5">
        <legend class="mb-2 text-sm font-medium">Dauer</legend>
        <div class="flex flex-wrap gap-2">
          {#each optionen as option (option)}
            <button
              type="button"
              onclick={() => (dauerWahl = option)}
              class="rounded-full px-4 py-2 text-sm font-medium transition
                     {dauer === option
                ? 'bg-foreground text-background'
                : 'border border-border text-muted-foreground'}"
              aria-pressed={dauer === option}
            >
              {option >= 60 ? `${option / 60} h`.replace('.5', '½') : `${option} min`}
            </button>
          {/each}
        </div>
      </fieldset>

      <!-- Open-Match-Toggle: der Brueckenschlag ins Elo-Oekosystem -->
      <div class="mt-5 rounded-2xl border border-border p-4">
        <label class="flex cursor-pointer items-start gap-3">
          <input
            type="checkbox"
            bind:checked={offenesMatch}
            class="mt-0.5 size-5 shrink-0 rounded accent-[var(--color-primary)]"
          />
          <span class="flex-1">
            <span class="block text-sm font-medium">Als offenes Match einstellen</span>
            <span class="block text-xs text-muted-foreground">
              Sichtbar auf {auswahl.court.sport === 'padel' ? 'PadelIndex' : 'TennisIndex'} –
              Mitspieler finden dich über deine Elo.
            </span>
          </span>
        </label>

        {#if offenesMatch}
          <div class="mt-3 flex items-center gap-3 border-t border-border pt-3">
            <span class="text-sm text-muted-foreground">Spieler gesucht</span>
            <div class="ml-auto flex gap-1">
              {#each [1, 2, 3] as anzahl (anzahl)}
                <button
                  type="button"
                  onclick={() => (spielerGesucht = anzahl)}
                  class="size-9 rounded-full text-sm font-medium transition
                         {spielerGesucht === anzahl
                    ? 'bg-foreground text-background'
                    : 'border border-border text-muted-foreground'}"
                  aria-pressed={spielerGesucht === anzahl}
                >
                  {anzahl}
                </button>
              {/each}
            </div>
          </div>
        {/if}
      </div>

      <!-- Preis + Buchen -->
      <div class="mt-5 flex items-center justify-between">
        <div>
          <p class="text-xs text-muted-foreground">Preis</p>
          <p class="text-xl font-semibold tabular-nums {preisLaeuft ? 'opacity-40' : ''}">
            {preisText}
          </p>
        </div>

        {#if angemeldet}
          <form
            method="POST"
            action="?/buchen"
            use:enhance={() => {
              sendet = true;
              return async ({ update }) => {
                await update();
                sendet = false;
              };
            }}
          >
            <input type="hidden" name="court_id" value={auswahl.court.id} />
            <input type="hidden" name="starts_at" value={auswahl.slot.start.toISOString()} />
            <input type="hidden" name="ends_at" value={ende?.toISOString()} />
            <input type="hidden" name="offenes_match" value={offenesMatch ? '1' : ''} />
            <input type="hidden" name="spieler_gesucht" value={spielerGesucht} />
            <button
              type="submit"
              disabled={sendet}
              class="rounded-full bg-primary px-7 py-3 font-medium text-primary-foreground
                     transition active:scale-[0.98] disabled:opacity-60"
            >
              {sendet ? 'Bucht…' : 'Buchen'}
            </button>
          </form>
        {:else}
          <a
            href="/login?weiter={encodeURIComponent(
              `/buchen/${plan.club.slug}?datum=${plan.date}`
            )}"
            class="rounded-full bg-primary px-7 py-3 font-medium text-primary-foreground"
          >
            Anmelden & buchen
          </a>
        {/if}
      </div>
    </div>
  </div>
{/if}
