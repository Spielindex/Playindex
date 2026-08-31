import { redirect } from '@sveltejs/kit';
import { PUBLIC_DEFAULT_CLUB } from '$env/static/public';
import type { PageServerLoad } from './$types';

/**
 * Die Startseite ist kein Marketing-Zwischenschritt, sondern leitet direkt
 * ins Grid. Klick 1 von 3 wird nicht fuer eine Landingpage verschwendet.
 */
export const load: PageServerLoad = async () => {
  redirect(307, `/buchen/${PUBLIC_DEFAULT_CLUB}`);
};
