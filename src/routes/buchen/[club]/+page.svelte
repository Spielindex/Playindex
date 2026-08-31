<script lang="ts">
  import type { PageData } from './$types';

  let { data }: { data: PageData } = $props();

  const plan = $derived(data.plan);
  const zone = $derived(plan.club.timezone);

  function uhrzeit(iso: string): string {
    return new Intl.DateTimeFormat('de-DE', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: zone
    }).format(new Date(iso));
  }

  function tagWechseln(tage: number): string {
    const d = new Date(`${data.datum}T12:00:00Z`);
    d.setUTCDate(d.getUTCDate() + tage);
    const naechstes = d.toISOString().slice(0, 10);
    const sport = data.sport ? `&sport=${data.sport}` : '';
    return `?datum=${naechstes}${sport}`;
  }
</script>

<svelte:head>
  <title>{plan.club.name} · Platz buchen</title>
  <meta name="description" content="Padel- und Tennisplätze im {plan.club.name} online buchen." />
</svelte:head>

<div class="mx-auto w-full max-w-6xl px-4 py-6">
  <div class="mb-6 flex items-center justify-between gap-3">
    <div>
      <h1 class="text-2xl font-semibold tracking-tight">{plan.club.name}</h1>
      <p class="text-sm text-muted-foreground">
        {new Intl.DateTimeFormat('de-DE', { weekday: 'long', day: 'numeric', month: 'long' }).format(
          new Date(`${data.datum}T12:00:00Z`)
        )}
      </p>
    </div>
    <div class="flex gap-1">
      <a
        href={tagWechseln(-1)}
        class="rounded-full border border-border px-3 py-1.5 text-sm"
        aria-label="Vorheriger Tag">←</a
      >
      <a
        href={tagWechseln(1)}
        class="rounded-full border border-border px-3 py-1.5 text-sm"
        aria-label="Nächster Tag">→</a
      >
    </div>
  </div>

  <nav class="mb-6 flex gap-2" aria-label="Sportart">
    {#each [{ wert: null, label: 'Alle' }, { wert: 'padel', label: 'Padel' }, { wert: 'tennis', label: 'Tennis' }] as filter (filter.label)}
      <a
        href="?datum={data.datum}{filter.wert ? `&sport=${filter.wert}` : ''}"
        class="rounded-full px-4 py-1.5 text-sm font-medium transition
               {data.sport === filter.wert
          ? 'bg-foreground text-background'
          : 'border border-border text-muted-foreground'}"
      >
        {filter.label}
      </a>
    {/each}
  </nav>

  <!--
    Platzhalter. Schritt 3 ersetzt diesen Block durch <BookingGrid {plan} />
    mit horizontalem Scroll, Slot-Rastern und Tap-to-Book. Die Daten stehen
    hier bereits vollstaendig und in der richtigen Form bereit.
  -->
  <div class="space-y-3">
    {#each plan.courts as platz (platz.id)}
      <section class="rounded-2xl border border-border bg-card p-4">
        <header class="mb-2 flex items-baseline justify-between">
          <h2 class="font-medium">{platz.name}</h2>
          <span class="text-xs text-muted-foreground">
            {platz.opens_at ? `${platz.opens_at.slice(0, 5)}–${platz.closes_at?.slice(0, 5)}` : 'geschlossen'}
          </span>
        </header>
        {#if platz.bookings.length === 0}
          <p class="text-sm text-free-foreground">Ganzer Tag frei</p>
        {:else}
          <ul class="flex flex-wrap gap-2">
            {#each platz.bookings as b (b.id)}
              <li
                class="rounded-lg px-2.5 py-1 text-xs
                       {b.is_open_match ? 'bg-match/20 text-foreground' : 'bg-busy text-muted-foreground'}"
              >
                {uhrzeit(b.starts_at)}–{uhrzeit(b.ends_at)}
                {#if b.is_open_match}<span class="font-medium"> · sucht {b.players_needed}</span>{/if}
              </li>
            {/each}
          </ul>
        {/if}
      </section>
    {:else}
      <p class="text-sm text-muted-foreground">Für diesen Filter gibt es keine Plätze.</p>
    {/each}
  </div>
</div>
