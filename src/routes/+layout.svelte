<script lang="ts">
  import '../app.css';
  import { invalidate } from '$app/navigation';
  import { onMount } from 'svelte';
  import type { LayoutData } from './$types';
  import type { Snippet } from 'svelte';

  let { data, children }: { data: LayoutData; children: Snippet } = $props();

  const user = $derived(data.user);

  onMount(() => {
    const {
      data: { subscription }
    } = data.supabase.auth.onAuthStateChange((_ereignis, neueSession) => {
      if (neueSession?.expires_at !== data.session?.expires_at) invalidate('supabase:auth');
    });
    return () => subscription.unsubscribe();
  });
</script>

<div class="flex min-h-full flex-col">
  <header
    class="sticky top-0 z-30 border-b border-border bg-background/80 backdrop-blur-md
           supports-[backdrop-filter]:bg-background/60"
  >
    <nav class="mx-auto flex h-14 w-full max-w-6xl items-center gap-4 px-4">
      <a href="/" class="text-base font-semibold tracking-tight">Playindex</a>
      <div class="flex-1"></div>
      {#if user}
        <a href="/meine-buchungen" class="text-sm text-muted-foreground hover:text-foreground">
          Meine Buchungen
        </a>
        <form method="POST" action="/auth/logout">
          <button type="submit" class="text-sm text-muted-foreground hover:text-foreground">
            Abmelden
          </button>
        </form>
      {:else}
        <a
          href="/login"
          class="rounded-full bg-primary px-4 py-1.5 text-sm font-medium text-primary-foreground"
        >
          Anmelden
        </a>
      {/if}
    </nav>
  </header>

  <main class="flex-1">
    {@render children()}
  </main>
</div>
