import { createServerClient } from '@supabase/ssr';
import { redirect, type Handle } from '@sveltejs/kit';
import { sequence } from '@sveltejs/kit/hooks';
import { env as oeffentlich } from '$env/dynamic/public';
import type { Database } from '$lib/types/database';

/**
 * Legt pro Request einen Supabase-Client an, der seine Session in Cookies
 * haelt. Default-Schema ist `booking` - fuer das zentrale Profil wird per
 * `.schema('public')` umgeschaltet.
 *
 * `$env/dynamic/*` statt `$env/static/*`: statische Env wird zur BUILDZEIT
 * eingesetzt, was den Cloudflare-Build ohne gesetzte Variablen abbrechen
 * laesst. Dynamische Env kommt zur Laufzeit aus den Worker-Bindings - der
 * Build bleibt konfigurationsfrei und Secrets landen nicht im Bundle.
 */
const supabase: Handle = async ({ event, resolve }) => {
  event.locals.supabase = createServerClient<Database, 'booking'>(
    oeffentlich.PUBLIC_SUPABASE_URL,
    oeffentlich.PUBLIC_SUPABASE_ANON_KEY,
    {
      db: { schema: 'booking' },
      cookies: {
        getAll: () => event.cookies.getAll(),
        setAll: (cookiesToSet) => {
          for (const { name, value, options } of cookiesToSet) {
            event.cookies.set(name, value, { ...options, path: '/' });
          }
        }
      }
    }
  );

  /**
   * getSession() liest das JWT nur aus dem Cookie und prueft KEINE Signatur -
   * ein manipuliertes Cookie kaeme damit durch. Deshalb wird die Session hier
   * immer zusaetzlich per getUser() gegen Supabase verifiziert.
   */
  event.locals.safeGetSession = async () => {
    const {
      data: { session }
    } = await event.locals.supabase.auth.getSession();
    if (!session) return { session: null, user: null };

    const {
      data: { user },
      error
    } = await event.locals.supabase.auth.getUser();
    if (error) return { session: null, user: null };

    return { session, user };
  };

  return resolve(event, {
    filterSerializedResponseHeaders: (name) =>
      name === 'content-range' || name === 'x-supabase-api-version'
  });
};

/**
 * Zweite Verteidigungslinie. Der eigentliche Schutz sitzt in
 * `(konto)/+layout.server.ts` bzw. direkt in den Endpunkten - Layout-Loads
 * laufen bei `+server.ts`-Routen naemlich NICHT.
 */
const GESCHUETZT = ['/meine-buchungen', '/profil', '/admin'];

const authGuard: Handle = async ({ event, resolve }) => {
  const { session, user } = await event.locals.safeGetSession();
  event.locals.session = session;
  event.locals.user = user;

  const pfad = event.url.pathname;

  if (!session && GESCHUETZT.some((p) => pfad === p || pfad.startsWith(`${p}/`))) {
    redirect(303, `/login?weiter=${encodeURIComponent(pfad + event.url.search)}`);
  }

  if (session && (pfad === '/login' || pfad === '/registrieren')) {
    redirect(303, '/meine-buchungen');
  }

  return resolve(event);
};

export const handle: Handle = sequence(supabase, authGuard);
