import { fail, redirect } from '@sveltejs/kit';
import { sicheresZiel } from '$lib/server/sso';
import type { Actions } from './$types';

export const actions: Actions = {
  default: async ({ request, url, locals }) => {
    const formular = await request.formData();
    const email = String(formular.get('email') ?? '').trim();
    const passwort = String(formular.get('passwort') ?? '');

    if (!email || !passwort) {
      return fail(400, { email, fehler: 'Bitte E-Mail und Passwort angeben.' });
    }

    const { error } = await locals.supabase.auth.signInWithPassword({ email, password: passwort });

    // Bewusst dieselbe Meldung fuer "Konto existiert nicht" und "Passwort falsch":
    // sonst wird das Login-Formular zum Verzeichnis registrierter E-Mails.
    if (error) return fail(400, { email, fehler: 'E-Mail oder Passwort stimmt nicht.' });

    redirect(303, sicheresZiel(url.searchParams.get('weiter'), '/meine-buchungen'));
  }
};
