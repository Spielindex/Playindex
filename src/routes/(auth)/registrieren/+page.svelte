<script lang="ts">
  import { enhance } from '$app/forms';
  import type { ActionData } from './$types';

  let { form }: { form: ActionData } = $props();
</script>

<svelte:head><title>Registrieren · Playindex</title></svelte:head>

<div class="mx-auto w-full max-w-sm px-4 py-12">
  {#if form?.erfolg}
    <h1 class="text-2xl font-semibold tracking-tight">Fast geschafft</h1>
    <p class="mt-2 text-sm text-muted-foreground">
      Falls für <strong>{form.email}</strong> noch kein Konto bestand, liegt jetzt eine
      Bestätigungsmail im Postfach.
    </p>
  {:else}
    <h1 class="text-2xl font-semibold tracking-tight">Konto anlegen</h1>
    <p class="mt-1 text-sm text-muted-foreground">
      Hast du schon PadelIndex oder TennisIndex? Dann
      <a href="/login" class="text-foreground underline">melde dich einfach an</a>.
    </p>

    <form method="POST" class="mt-8 space-y-4" use:enhance>
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
          autocomplete="new-password"
          minlength="8"
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
        class="w-full rounded-xl bg-primary py-2.5 font-medium text-primary-foreground"
      >
        Registrieren
      </button>
    </form>
  {/if}
</div>
