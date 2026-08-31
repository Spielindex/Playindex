import type { Session, SupabaseClient, User } from '@supabase/supabase-js';
import type { Database } from '$lib/types/database';

declare global {
  namespace App {
    interface Locals {
      supabase: SupabaseClient<Database, 'booking'>;
      /**
       * Liefert Session UND einen serverseitig bei Supabase verifizierten User.
       * `getSession()` allein prueft die JWT-Signatur nicht - deshalb nie direkt
       * verwenden, immer diesen Helfer.
       */
      safeGetSession: () => Promise<{ session: Session | null; user: User | null }>;
      session: Session | null;
      user: User | null;
    }
    interface PageData {
      session: Session | null;
      user: User | null;
    }
    // eslint-disable-next-line @typescript-eslint/no-empty-object-type
    interface Platform {}
  }
}

export {};
