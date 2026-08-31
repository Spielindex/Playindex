import { fail } from '@sveltejs/kit';
import { PUBLIC_SITE_URL } from '$env/static/public';
import type { Actions } from './$types';

export const actions: Actions = {
  default: async ({ request, locals }) => {
    const formular = await request.formData();
    const email = String(formular.get('email') ?? '').trim();
    const passwort = String(formular.get('passwort') ?? '');

    if (passwort.length < 8) {
      return fail(400, { email, fehler: 'Das Passwort braucht mindestens 8 Zeichen.' });
    }

    const { error } = await locals.supabase.auth.signUp({
      email,
      password: passwort,
      options: { emailRedirectTo: `${PUBLIC_SITE_URL}/auth/confirm` }
    });

    if (error) return fail(400, { email, fehler: 'Registrierung fehlgeschlagen.' });

    // Immer dieselbe Antwort - auch bei bereits vergebener E-Mail.
    return { erfolg: true, email };
  }
};
