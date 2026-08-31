import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import type { DaySchedule, Sport } from '$lib/types/database';

const SPORTARTEN: Sport[] = ['padel', 'tennis'];

function heuteInZone(zone: string): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: zone }).format(new Date());
}

/**
 * Ein einziger RPC liefert alles, was das Grid braucht - Clubregeln, Plaetze,
 * Oeffnungszeiten, Belegung, offene Matches und Sperrungen.
 *
 * Bewusst serverseitig: die Seite ist ohne Login vollstaendig nutzbar und
 * damit von Cloudflare cachebar, sobald wir das wollen.
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

  const plan = data as unknown as DaySchedule;

  // Belegung aendert sich staendig - kurz cachen, aber revalidieren lassen.
  setHeaders({ 'cache-control': 'private, max-age=0, must-revalidate' });

  return { plan, datum, sport };
};
