import { error, fail, redirect } from '@sveltejs/kit';
import type { Actions, PageServerLoad } from './$types';
import type { DaySchedule, OpenMatchPayload, Sport } from '$lib/types/database';

const SPORTARTEN: Sport[] = ['padel', 'tennis'];

function heuteInZone(zone: string): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: zone }).format(new Date());
}

/**
 * Ein einziger RPC liefert alles, was das Grid braucht - Clubregeln, Plaetze,
 * Oeffnungszeiten, Belegung, offene Matches und Sperrungen.
 *
 * Bewusst serverseitig: die Seite ist ohne Login vollstaendig nutzbar.
 */
export const load: PageServerLoad = async ({ params, url, locals, setHeaders }) => {
  const sportParam = url.searchParams.get('sport');
  const sport = SPORTARTEN.includes(sportParam as Sport) ? (sportParam as Sport) : null;

  // Ohne Datum: heute in der Zeitzone des Clubs, nicht in der des Servers.
  const datum = url.searchParams.get('datum') ?? heuteInZone('Europe/Berlin');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(datum)) error(400, 'Ungueltiges Datum');

  const { data, error: dbFehler } = await locals.supabase.rpc('get_day_schedule', {
    p_club_slug: params.club,
    p_date: datum,
    p_sport: sport
  });

  if (dbFehler) {
    if (dbFehler.code === 'P0002' || dbFehler.message.includes('nicht gefunden')) {
      error(404, 'Diesen Club gibt es nicht.');
    }
    error(500, 'Der Belegungsplan konnte nicht geladen werden.');
  }

  setHeaders({ 'cache-control': 'private, max-age=0, must-revalidate' });

  return { plan: data as unknown as DaySchedule, datum, sport };
};

export const actions: Actions = {
  buchen: async ({ request, locals, url }) => {
    const { session } = await locals.safeGetSession();
    if (!session) redirect(303, `/login?weiter=${encodeURIComponent(url.pathname + url.search)}`);

    const formular = await request.formData();
    const courtId = String(formular.get('court_id') ?? '');
    const startsAt = String(formular.get('starts_at') ?? '');
    const endsAt = String(formular.get('ends_at') ?? '');
    const offenesMatch = formular.get('offenes_match') === '1';
    const spielerGesucht = Number(formular.get('spieler_gesucht') ?? 1);

    if (!courtId || !startsAt || !endsAt) {
      return fail(400, { fehler: 'Unvollständige Anfrage.' });
    }

    const openMatch: OpenMatchPayload | null = offenesMatch
      ? {
          enabled: true,
          players_needed: Math.min(Math.max(spielerGesucht, 1), 3),
          visibility: 'public'
        }
      : null;

    // Preis, Öffnungszeiten, Vorlauf, Kontingent und Überschneidungsfreiheit
    // prüft die Datenbank. Diese Action leitet nur weiter und übersetzt Fehler.
    const { data, error: dbFehler } = await locals.supabase.rpc('create_booking', {
      p_court_id: courtId,
      p_starts_at: startsAt,
      p_ends_at: endsAt,
      p_open_match: openMatch
    });

    if (dbFehler) {
      // 23P01 = exclusion_violation: jemand war in genau diesem Moment schneller.
      if (dbFehler.code === '23P01') {
        return fail(409, {
          fehler: 'Dieser Slot wurde gerade vergeben. Bitte wähle einen anderen.'
        });
      }
      return fail(400, { fehler: dbFehler.message });
    }

    return { gebucht: true, buchung: data };
  }
};
