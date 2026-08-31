import { redirect, type RequestHandler } from '@sveltejs/kit';

/**
 * Bewusst nur POST: ein GET-Logout laesst sich per <img src> oder fremdem
 * Link ausloesen. SvelteKit prueft bei POST zusaetzlich den Origin (csrf).
 */
export const POST: RequestHandler = async ({ locals }) => {
  await locals.supabase.auth.signOut();
  redirect(303, '/');
};
