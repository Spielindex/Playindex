<script lang="ts">
  import { invalidateAll } from '$app/navigation';
  import BookingGrid from '$lib/components/BookingGrid.svelte';
  import BookingSheet from '$lib/components/BookingSheet.svelte';
  import type { ScheduleCourt } from '$lib/types/database';
  import type { Slot } from '$lib/utils/zeit';
  import type { ActionData, PageData } from './$types';

  let { data, form }: { data: PageData; form: ActionData } = $props();

  const plan = $derived(data.plan);
  let auswahl = $state<{ court: ScheduleCourt; slot: Slot; maxDauer: number } | null>(null);

  // Sekundengenau ist unnoetig - die "Jetzt"-Linie darf eine Minute nachlaufen.
  let jetzt = $state(new Date());
  $effect(() => {
    const timer = setInterval(() => (jetzt = new Date()), 60_000);
    return () => clearInterval(timer);
  });

  // Nach erfolgreicher Buchung: Sheet zu, Grid neu laden.
  $effect(() => {
    if (form?.gebucht) {
      auswahl = null;
      void invalidateAll();
    }
  });

  /** Preis kommt vom Server - siehe booking.price_for_me. */
  async function preisAbfrage(courtId: string, start: Date, ende: Date) {
    const { data: cent, error } = await data.supabase.rpc('price_for_me', {
      p_court_id: courtId,
      p_starts_at: start.toISOString(),
      p_ends_at: ende.toISOString()
    });
    return error ? null : cent;
  }

  function tagWechseln(tage: number): string {
    const d = new Date(`${data.datum}T12:00:00Z`);
    d.setUTCDate(d.getUTCDate() + tage);
    const sport = data.sport ? `&sport=${data.sport}` : '';
    return `?datum=${d.toISOString().slice(0, 10)}${sport}`;
  }

  const tagTitel = $derived(
    new Intl.DateTimeFormat('de-DE', { weekday: 'long', day: 'numeric', month: 'long' }).format(
      new Date(`${data.datum}T12:00:00Z`)
    )
  );

  const filter = [
    { wert: null, label: 'Alle' },
    { wert: 'padel', label: 'Padel' },
    { wert: 'tennis', label: 'Tennis' }
  ] as const;
</script>

<svelte:head>
  <title>{plan.club.name} · Platz buchen</title>
  <meta name="description" content="Padel- und Tennisplätze im {plan.club.name} online buchen." />
</svelte:head>

<div class="mx-auto w-full max-w-5xl px-4 py-5">
  <div class="mb-4 flex items-start justify-between gap-3">
    <div>
      <h1 class="text-xl font-semibold tracking-tight sm:text-2xl">{plan.club.name}</h1>
      <p class="text-sm text-muted-foreground">{tagTitel}</p>
    </div>
    <div class="flex shrink-0 gap-1">
      <a
        href={tagWechseln(-1)}
        class="grid size-9 place-items-center rounded-full border border-border"
        aria-label="Vorheriger Tag">←</a
      >
      <a
        href={tagWechseln(1)}
        class="grid size-9 place-items-center rounded-full border border-border"
        aria-label="Nächster Tag">→</a
      >
    </div>
  </div>

  <nav class="mb-4 flex gap-2" aria-label="Sportart">
    {#each filter as f (f.label)}
      <a
        href="?datum={data.datum}{f.wert ? `&sport=${f.wert}` : ''}"
        aria-current={data.sport === f.wert ? 'page' : undefined}
        class="rounded-full px-4 py-1.5 text-sm font-medium transition
               {data.sport === f.wert
          ? 'bg-foreground text-background'
          : 'border border-border text-muted-foreground'}"
      >
        {f.label}
      </a>
    {/each}
  </nav>

  {#if form?.fehler}
    <p
      class="mb-4 rounded-xl bg-destructive/10 px-4 py-3 text-sm text-destructive"
      role="alert"
      aria-live="assertive"
    >
      {form.fehler}
    </p>
  {/if}

  {#if form?.gebucht}
    <p
      class="mb-4 rounded-xl bg-free px-4 py-3 text-sm text-free-foreground"
      role="status"
      aria-live="polite"
    >
      Platz gebucht. Du findest ihn unter
      <a href="/meine-buchungen" class="underline">Meine Buchungen</a>.
    </p>
  {/if}

  <BookingGrid
    {plan}
    datum={data.datum}
    {jetzt}
    onauswahl={(a) => (auswahl = a)}
  />
</div>

<BookingSheet
  {plan}
  {auswahl}
  angemeldet={!!data.user}
  {preisAbfrage}
  onschliessen={() => (auswahl = null)}
/>
