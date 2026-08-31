import { redirect, type RequestHandler } from '@sveltejs/kit';
import { sicheresZiel } from '$lib/server/sso';

/** OAuth- und PKCE-Rueckweg (Google, Apple, Magic Link aus einer E-Mail). */
export const GET: RequestHandler = async ({ url, locals }) => {
  const code = url.searchParams.get('code');
  const ziel = sicheresZiel(url.searchParams.get('weiter'), '/');

  if (code) {
    const { error } = await locals.supabase.auth.exchangeCodeForSession(code);
    if (!error) redirect(303, ziel);
  }

  redirect(303, '/login?fehler=callback');
};
