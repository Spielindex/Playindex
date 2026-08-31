import type { LayoutServerLoad } from './$types';

/**
 * Reicht Session und Cookies an den universellen Load weiter, damit der
 * Client-Supabase beim ersten Rendern schon dieselbe Session kennt.
 */
export const load: LayoutServerLoad = async ({ locals, cookies }) => ({
  session: locals.session,
  user: locals.user,
  cookies: cookies.getAll()
});
