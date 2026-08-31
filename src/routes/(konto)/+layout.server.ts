import { redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

/**
 * Schutz fuer alle Seiten dieser Gruppe.
 *
 * WICHTIG: Layout-Loads laufen NICHT fuer `+server.ts`-Endpunkte. Endpunkte,
 * die eine Session brauchen, muessen selbst pruefen - deshalb steht in
 * hooks.server.ts zusaetzlich eine pfadbasierte Absicherung.
 */
export const load: LayoutServerLoad = async ({ locals, url }) => {
  const { session, user } = await locals.safeGetSession();
  if (!session || !user) {
    redirect(303, `/login?weiter=${encodeURIComponent(url.pathname + url.search)}`);
  }
  return { user };
};
