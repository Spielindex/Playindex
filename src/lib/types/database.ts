/**
 * Typen fuer das Playindex-Schema.
 *
 * Handgepflegt, solange das Supabase-Projekt noch nicht steht. Sobald es
 * erreichbar ist, ersetzen durch:
 *
 *   supabase gen types typescript --project-id <ref> --schema booking,public \
 *     > src/lib/types/database.ts
 *
 * Die Struktur entspricht exakt der Ausgabe des Generators, damit der Wechsel
 * ein reiner Dateiaustausch ist.
 *
 * WICHTIG: durchgehend `type` statt `interface`. Interfaces bekommen in
 * TypeScript keine implizite Index-Signatur und erfuellen damit
 * `Record<string, unknown>` nicht - postgrest-js loest das Schema dann auf
 * `never` auf und jede Query verliert ihre Typen.
 */

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Sport = 'padel' | 'tennis';
export type BookingStatus = 'pending' | 'confirmed' | 'cancelled' | 'no_show' | 'completed';
export type BookingType = 'player' | 'subscription' | 'course' | 'tournament' | 'maintenance';
export type MembershipTier = 'guest' | 'member' | 'subscriber';
export type StaffRole = 'owner' | 'admin' | 'staff';
export type ParticipantStatus = 'invited' | 'accepted' | 'declined';
export type PaymentStatus = 'unpaid' | 'pending' | 'paid' | 'refunded' | 'waived';
export type OpenMatchStatus = 'open' | 'full' | 'closed' | 'cancelled';
export type IndexPlatform = 'padelindex' | 'tennisindex';

export type ClubRow = {
  id: string;
  slug: string;
  name: string;
  timezone: string;
  city: string | null;
  currency: string;
  slot_minutes: number;
  min_duration_minutes: number;
  max_duration_minutes: number;
  max_advance_days: number;
  cancellation_deadline_hours: number;
  max_open_bookings_per_user: number;
  is_active: boolean;
}

export type CourtRow = {
  id: string;
  club_id: string;
  slug: string;
  name: string;
  sport: Sport;
  surface: string | null;
  is_indoor: boolean;
  has_floodlight: boolean;
  max_players: number;
  sort_order: number;
  is_active: boolean;
}

export type BookingRow = {
  id: string;
  club_id: string;
  court_id: string;
  starts_at: string;
  ends_at: string;
  type: BookingType;
  status: BookingStatus;
  booked_by: string | null;
  player_count: number;
  price_cents: number;
  currency: string;
  title: string | null;
  note: string | null;
  cancelled_at: string | null;
  cancellation_reason: string | null;
  source: string;
  created_at: string;
}

export type OpenMatchRow = {
  booking_id: string;
  sport: Sport;
  platform: IndexPlatform;
  status: OpenMatchStatus;
  players_needed: number;
  level_min: number | null;
  level_max: number | null;
  gender_preference: 'any' | 'men' | 'women' | 'mixed';
  visibility: 'public' | 'club' | 'friends';
  description: string | null;
  is_ranked: boolean;
  external_match_id: string | null;
  external_url: string | null;
}

export type BookingParticipantRow = {
  id: string;
  booking_id: string;
  user_id: string | null;
  guest_name: string | null;
  guest_email: string | null;
  is_host: boolean;
  status: ParticipantStatus;
  share_cents: number;
  paid_cents: number;
  payment_status: PaymentStatus;
}

export type ClubMemberRow = {
  club_id: string;
  user_id: string;
  tier: MembershipTier;
  member_number: string | null;
  phone: string | null;
  credit_cents: number;
  no_show_count: number;
  is_blocked: boolean;
}

export type PlayerRow = {
  user_id: string;
  display_name: string;
  avatar_url: string | null;
  padel_elo: number | null;
  tennis_elo: number | null;
}

/* -------------------------------------------------------------------------- */
/* Rueckgabe von booking.get_day_schedule()                                    */
/* -------------------------------------------------------------------------- */

export type ScheduleBooking = {
  id: string;
  starts_at: string;
  ends_at: string;
  status: BookingStatus;
  type: BookingType;
  is_open_match: boolean;
  players_needed: number | null;
  level_min: number | null;
  level_max: number | null;
  is_mine: boolean;
}

export type ScheduleCourt = {
  id: string;
  slug: string;
  name: string;
  sport: Sport;
  surface: string | null;
  is_indoor: boolean;
  max_players: number;
  /** Lokale Wandzeit "HH:MM:SS", null = an diesem Tag geschlossen */
  opens_at: string | null;
  closes_at: string | null;
  bookings: ScheduleBooking[];
}

export type DaySchedule = {
  club: Pick<
    ClubRow,
    | 'id'
    | 'slug'
    | 'name'
    | 'timezone'
    | 'currency'
    | 'slot_minutes'
    | 'min_duration_minutes'
    | 'max_duration_minutes'
    | 'max_advance_days'
    | 'cancellation_deadline_hours'
  >;
  date: string;
  closures: { court_id: string | null; starts_at: string; ends_at: string; reason: string | null }[];
  courts: ScheduleCourt[];
}

export type OpenMatchPayload = {
  enabled?: boolean;
  players_needed?: number;
  level_min?: number | null;
  level_max?: number | null;
  gender_preference?: 'any' | 'men' | 'women' | 'mixed';
  visibility?: 'public' | 'club' | 'friends';
  description?: string | null;
}

/* -------------------------------------------------------------------------- */

type Table<Row, Insert = Partial<Row>, Update = Partial<Row>> = {
  Row: Row;
  Insert: Insert;
  Update: Update;
  Relationships: [];
};

export type Database = {
  booking: {
    Tables: {
      clubs: Table<ClubRow>;
      courts: Table<CourtRow>;
      bookings: Table<BookingRow>;
      booking_participants: Table<BookingParticipantRow>;
      open_matches: Table<OpenMatchRow>;
      club_members: Table<ClubMemberRow>;
    };
    Views: {
      v_player: Table<PlayerRow>;
      v_court_availability: Table<{
        booking_id: string;
        club_id: string;
        court_id: string;
        starts_at: string;
        ends_at: string;
        status: BookingStatus;
        type: BookingType;
        is_open_match: boolean;
        players_needed: number | null;
        level_min: number | null;
        level_max: number | null;
      }>;
      v_open_matches: Table<{
        booking_id: string;
        sport: Sport;
        platform: IndexPlatform;
        players_needed: number;
        level_min: number | null;
        level_max: number | null;
        starts_at: string;
        ends_at: string;
        court_name: string;
        club_slug: string;
        club_name: string;
        players_joined: number;
      }>;
    };
    Functions: {
      get_day_schedule: {
        Args: { p_club_slug: string; p_date: string; p_sport?: Sport | null };
        Returns: DaySchedule;
      };
      create_booking: {
        Args: {
          p_court_id: string;
          p_starts_at: string;
          p_ends_at: string;
          p_player_count?: number | null;
          p_note?: string | null;
          p_open_match?: OpenMatchPayload | null;
          p_participants?: Json;
        };
        Returns: BookingRow;
      };
      cancel_booking: {
        Args: { p_booking_id: string; p_reason?: string | null };
        Returns: BookingRow;
      };
      calculate_price: {
        Args: { p_court_id: string; p_starts_at: string; p_ends_at: string; p_user_id?: string | null };
        Returns: number;
      };
    };
    Enums: {
      sport: Sport;
      booking_status: BookingStatus;
      booking_type: BookingType;
      membership_tier: MembershipTier;
      staff_role: StaffRole;
      participant_status: ParticipantStatus;
      payment_status: PaymentStatus;
      open_match_status: OpenMatchStatus;
      index_platform: IndexPlatform;
    };
    CompositeTypes: Record<string, never>;
  };
  public: {
    Tables: {
      profiles: Table<{
        id: string;
        display_name: string | null;
        avatar_url: string | null;
        padel_elo: number | null;
        tennis_elo: number | null;
      }>;
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
