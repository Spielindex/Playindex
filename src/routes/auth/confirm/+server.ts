import { redirect, type RequestHandler } from '@sveltejs/kit';
import type { EmailOtpType } from '@supabase/supabase-js';
import { sicheresZiel } from '$lib/server/sso';

/** Bestaetigungslinks aus E-Mails (Registrierung, Passwort-Reset, Mailwechsel). */
export const GET: RequestHandler = async ({ url, locals }) => {
  const tokenHash = url.searchParams.get('token_hash');
  const typ = url.searchParams.get('type') as EmailOtpType | null;
  const ziel = sicheresZiel(url.searchParams.get('weiter'), '/');

  if (tokenHash && typ) {
    const { error } = await locals.supabase.auth.verifyOtp({ type: typ, token_hash: tokenHash });
    if (!error) redirect(303, ziel);
  }

  redirect(303, '/login?fehler=bestaetigung');
};
