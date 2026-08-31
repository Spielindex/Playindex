import { fail } from '@sveltejs/kit';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ locals }) => {
  // RLS liefert von sich aus nur die eigenen Buchungen - kein Filter auf
  // user_id noetig und keine Moeglichkeit, ihn zu vergessen.
  const { data, error } = await locals.supabase
    .from('bookings')
    .select('id, starts_at, ends_at, status, price_cents, currency, court_id, courts(name, sport)')
    .in('status', ['pending', 'confirmed'])
    .gte('starts_at', new Date().toISOString())
    .order('starts_at', { ascending: true });

  return { buchungen: data ?? [], ladefehler: error?.message ?? null };
};

export const actions: Actions = {
  stornieren: async ({ request, locals }) => {
    const formular = await request.formData();
    const id = String(formular.get('id') ?? '');
    if (!id) return fail(400, { fehler: 'Keine Buchung angegeben.' });

    // Berechtigung und Stornofrist prueft die Datenbank, nicht diese Route.
    const { error } = await locals.supabase.rpc('cancel_booking', {
      p_booking_id: id,
      p_reason: null
    });

    if (error) return fail(400, { fehler: error.message });
    return { storniert: true };
  }
};
