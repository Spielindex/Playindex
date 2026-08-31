import { createClient } from '@supabase/supabase-js';
import { SUPABASE_SERVICE_ROLE_KEY } from '$env/static/private';
import { PUBLIC_SUPABASE_URL } from '$env/static/public';
import type { Database } from '$lib/types/database';

const optionen = {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false }
} as const;

/**
 * Service-Role-Client. Umgeht RLS vollstaendig.
 *
 * Dieses Modul liegt in `src/lib/server/**` - SvelteKit bricht den Build ab,
 * wenn es je aus Client-Code importiert wird. Das ist die wichtigste
 * Einzelmassnahme gegen ein geleaktes Service-Role-Key.
 *
 * Erlaubte Aufrufer: /auth/handoff, /api/sso/ticket, spaeter Zahlungs-Webhooks.
 */
export const supabaseAdmin = createClient<Database, 'booking'>(
  PUBLIC_SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  { ...optionen, db: { schema: 'booking' } }
);

/** Signaturen der SSO-Funktionen (Schema `sso`, nur fuer service_role). */
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

export const ssoAdmin = createClient<SsoDatabase, 'sso'>(
  PUBLIC_SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  { ...optionen, db: { schema: 'sso' } }
);
