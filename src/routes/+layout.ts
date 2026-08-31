import { createBrowserClient, createServerClient, isBrowser } from '@supabase/ssr';
import { env as oeffentlich } from '$env/dynamic/public';
import type { Database } from '$lib/types/database';
import type { LayoutLoad } from './$types';

export const load: LayoutLoad = async ({ data, depends, fetch }) => {
  // Marker, den onAuthStateChange invalidiert -> Session-Wechsel rendert neu.
  depends('supabase:auth');

  const supabase = isBrowser()
    ? createBrowserClient<Database, 'booking'>(oeffentlich.PUBLIC_SUPABASE_URL, oeffentlich.PUBLIC_SUPABASE_ANON_KEY, {
        db: { schema: 'booking' },
        global: { fetch }
      })
    : createServerClient<Database, 'booking'>(oeffentlich.PUBLIC_SUPABASE_URL, oeffentlich.PUBLIC_SUPABASE_ANON_KEY, {
        db: { schema: 'booking' },
        global: { fetch },
        cookies: { getAll: () => data.cookies }
      });

  const {
    data: { session }
  } = await supabase.auth.getSession();

  return { supabase, session, user: data.user };
};
