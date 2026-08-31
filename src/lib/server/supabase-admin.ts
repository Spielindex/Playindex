import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { env as geheim } from '$env/dynamic/private';
import { env as oeffentlich } from '$env/dynamic/public';
import type { Database } from '$lib/types/database';

const optionen = {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false }
} as const;

/**
 * Signaturen der SSO-Funktionen (Schema `sso`, nur fuer service_role).
 */
type SsoDatabase = {
  sso: {
    Tables: Record<string, never>;
    Views: Record<string, never>;
    Functions: {
      issue_handoff_token: {
        Args: {
          p_user_id: string;
          p_issued_by: string;
          p_redirect_to?: string | null;
          p_user_agent?: string | null;
          p_ip?: string | null;
        };
        Returns: string;
      };
      consume_handoff_token: {
        Args: { p_token: string };
        Returns: { user_id: string; redirect_to: string | null; issued_by: string }[];
      };
      resolve_identity: {
        Args: { p_source: string; p_external_user_id: string; p_email: string | null };
        Returns: string | null;
      };
      link_identity: {
        Args: {
          p_source: string;
          p_external_user_id: string;
          p_user_id: string;
          p_email?: string | null;
          p_method?: string;
        };
        Returns: undefined;
      };
      claim_nonce: { Args: { p_nonce: string; p_source: string }; Returns: boolean };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};

function konfiguration() {
  const url = oeffentlich.PUBLIC_SUPABASE_URL;
  const key = geheim.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error(
      'PUBLIC_SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY müssen gesetzt sein ' +
        '(Cloudflare: Settings → Variables and Secrets).'
    );
  }
  return { url, key };
}

let cacheAdmin: SupabaseClient<Database, 'booking'> | null = null;
let cacheSso: SupabaseClient<SsoDatabase, 'sso'> | null = null;

/**
 * Service-Role-Client. Umgeht RLS vollstaendig.
 *
 * Dieses Modul liegt in `src/lib/server/**` - SvelteKit bricht den Build ab,
 * wenn es je aus Client-Code importiert wird. Das ist die wichtigste
 * Einzelmassnahme gegen ein geleaktes Service-Role-Key.
 *
 * Bewusst LAZY: auf Cloudflare Workers stehen die Bindings aus
 * `$env/dynamic/private` erst innerhalb eines Requests bereit. Ein Client, der
 * beim Laden des Moduls gebaut wird, bekaeme ein leeres Key.
 *
 * Erlaubte Aufrufer: /auth/handoff, /api/sso/ticket, spaeter Zahlungs-Webhooks.
 */
export function supabaseAdmin(): SupabaseClient<Database, 'booking'> {
  if (!cacheAdmin) {
    const { url, key } = konfiguration();
    cacheAdmin = createClient<Database, 'booking'>(url, key, { ...optionen, db: { schema: 'booking' } });
  }
  return cacheAdmin;
}

/** Zugriff auf das `sso`-Schema. Ebenfalls nur mit service_role erreichbar. */
export function ssoAdmin(): SupabaseClient<SsoDatabase, 'sso'> {
  if (!cacheSso) {
    const { url, key } = konfiguration();
    cacheSso = createClient<SsoDatabase, 'sso'>(url, key, { ...optionen, db: { schema: 'sso' } });
  }
  return cacheSso;
}
