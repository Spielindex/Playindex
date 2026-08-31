# Playindex

Platzbuchung für das **Sportcenter Hahn** (Padel & Tennis), nativ verbunden mit
dem Matchmaking- und Elo-Ökosystem von [padelindex.de](https://padelindex.de)
und [tennisindex.eu](https://tennisindex.eu).

**Stack:** SvelteKit (TypeScript) · Supabase (PostgreSQL, Auth, RLS) ·
Tailwind CSS + shadcn-svelte · Cloudflare Pages

## Stand

| Schritt | Inhalt | Status |
|---|---|---|
| 1 | Datenbank-Architektur (Schema, RLS, Logik) | ✅ fertig & getestet |
| 2 | SvelteKit Auth & Routing, SSO-Implementierung | ✅ fertig & getestet |
| 3 | `BookingGrid.svelte` | ✅ fertig & getestet |

## Dokumentation

- [Datenbank-Architektur](docs/01-datenbank-architektur.md) – Datenmodell,
  Entscheidungen, API-Oberfläche
- [Cross-Login / SSO](docs/02-sso-cross-login.md) – warum ein gemeinsames
  Auth-Projekt und wie der domainübergreifende Wechsel funktioniert
- [SvelteKit-Struktur](docs/03-sveltekit-struktur.md) – Route-Konzept,
  Session-Handling und die Brücke zwischen zwei Supabase-Projekten
- [BookingGrid](docs/04-bookinggrid.md) – Aufbau des Grids, Zeitzonen-Logik
  und die vier Layout-Bugs, die erst im echten Browser sichtbar wurden

## Loslegen

```bash
npm install
cp .env.example .env      # Werte eintragen
npm run dev
```

Datenbank:

```bash
supabase db push          # oder: Migrationen der Reihe nach im SQL-Editor
psql "$DATABASE_URL" -f supabase/seed.sql
```

Danach im Dashboard unter **Settings → API → Exposed schemas** die Schemas
`booking` und `sso` ergänzen.

## Tests

```bash
./supabase/tests/run.sh   # 25 Assertions gegen ein lokales Postgres (≥ 14)
npm test                  # SSO-Krypto + Zeitlogik + Typprüfung
```

Die DB-Tests decken Preislogik, Doppelbuchungsschutz, Buchungsregeln,
RLS-Sichtbarkeit, Open-Match-Beitritt, anonymen Grid-Zugriff, den SSO-Handoff
und die Identitäts-Brücke ab. Sie brauchen kein Supabase, nur ein lokales
Postgres.

## Struktur

```
src/
  routes/       Route-Konzept siehe docs/03
  lib/components/  BookingGrid + BookingSheet
  lib/utils/    Zeitzonen- und Slot-Logik
  lib/server/   service_role + SSO – nie aus Client-Code importierbar
supabase/
  migrations/   11 Migrationen, idempotent, in Reihenfolge ausführbar
  seed.sql      Startdaten Sportcenter Hahn (Platzhalter – bitte anpassen)
  tests/        Verhaltenstests + minimaler Supabase-Stub
examples/
  partner/      Handoff-Endpunkt für padelindex.de / tennisindex.eu
docs/           Architekturdokumentation
```
