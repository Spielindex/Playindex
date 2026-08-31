import { redirect } from '@sveltejs/kit';
import { env as oeffentlich } from '$env/dynamic/public';
import type { PageServerLoad } from './$types';

/**
 * Die Startseite ist kein Marketing-Zwischenschritt, sondern leitet direkt
 * ins Grid. Klick 1 von 3 wird nicht fuer eine Landingpage verschwendet.
 */
export const load: PageServerLoad = async () => {
  redirect(307, `/buchen/${oeffentlich.PUBLIC_DEFAULT_CLUB ?? 'sportcenter-hahn'}`);
};
