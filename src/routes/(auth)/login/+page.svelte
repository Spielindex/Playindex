<script lang="ts">
  import { enhance } from '$app/forms';
  import type { ActionData } from './$types';

  let { form }: { form: ActionData } = $props();
  let laeuft = $state(false);
</script>

<svelte:head><title>Anmelden · Playindex</title></svelte:head>

<div class="mx-auto w-full max-w-sm px-4 py-12">
  <h1 class="text-2xl font-semibold tracking-tight">Anmelden</h1>
  <p class="mt-1 text-sm text-muted-foreground">
    Dein Zugang von PadelIndex oder TennisIndex funktioniert hier genauso.
  </p>

  <form
    method="POST"
    class="mt-8 space-y-4"
    use:enhance={() => {
      laeuft = true;
      return async ({ update }) => {
        await update();
        laeuft = false;
      };
    }}
  >
    <div>
      <label for="email" class="mb-1.5 block text-sm font-medium">E-Mail</label>
      <input
        id="email"
        name="email"
        type="email"
        autocomplete="email"
        required
        value={form?.email ?? ''}
        class="w-full rounded-xl border border-border bg-card px-3 py-2.5 outline-none
               focus:border-primary focus:ring-2 focus:ring-primary/20"
      />
    </div>

    <div>
      <label for="passwort" class="mb-1.5 block text-sm font-medium">Passwort</label>
      <input
        id="passwort"
        name="passwort"
        type="password"
        autocomplete="current-password"
        required
        class="w-full rounded-xl border border-border bg-card px-3 py-2.5 outline-none
               focus:border-primary focus:ring-2 focus:ring-primary/20"
      />
    </div>

    {#if form?.fehler}
      <p class="text-sm text-destructive" role="alert">{form.fehler}</p>
    {/if}

    <button
      type="submit"
      disabled={laeuft}
      class="w-full rounded-xl bg-primary py-2.5 font-medium text-primary-foreground
             disabled:opacity-60"
    >
      {laeuft ? 'Einen Moment…' : 'Anmelden'}
    </button>
  </form>

  <p class="mt-6 text-center text-sm text-muted-foreground">
    Noch kein Konto? <a href="/registrieren" class="text-foreground underline">Registrieren</a>
  </p>
</div>
