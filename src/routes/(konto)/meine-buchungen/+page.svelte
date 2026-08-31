<script lang="ts">
  import { enhance } from '$app/forms';
  import type { ActionData, PageData } from './$types';

  let { data, form }: { data: PageData; form: ActionData } = $props();

  const formatiert = new Intl.DateTimeFormat('de-DE', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Europe/Berlin'
  });
</script>

<svelte:head><title>Meine Buchungen · Playindex</title></svelte:head>

<div class="mx-auto w-full max-w-2xl px-4 py-8">
  <h1 class="text-2xl font-semibold tracking-tight">Meine Buchungen</h1>

  {#if form?.fehler}
    <p class="mt-4 rounded-xl bg-destructive/10 px-4 py-3 text-sm text-destructive" role="alert">
      {form.fehler}
    </p>
  {/if}

  <ul class="mt-6 space-y-3">
    {#each data.buchungen as b (b.id)}
      <li class="flex items-center justify-between rounded-2xl border border-border bg-card p-4">
        <div>
          <p class="font-medium">{formatiert.format(new Date(b.starts_at))}</p>
          <p class="text-sm text-muted-foreground">
            {(b.price_cents / 100).toLocaleString('de-DE', {
              style: 'currency',
              currency: b.currency
            })}
          </p>
        </div>
        <form method="POST" action="?/stornieren" use:enhance>
          <input type="hidden" name="id" value={b.id} />
          <button type="submit" class="text-sm text-muted-foreground underline hover:text-destructive">
            Stornieren
          </button>
        </form>
      </li>
    {:else}
      <li class="rounded-2xl border border-dashed border-border p-8 text-center">
        <p class="text-sm text-muted-foreground">Noch nichts gebucht.</p>
        <a href="/" class="mt-3 inline-block rounded-full bg-primary px-5 py-2 text-sm font-medium text-primary-foreground">
          Platz finden
        </a>
      </li>
    {/each}
  </ul>
</div>
