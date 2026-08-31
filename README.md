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
| 2 | SvelteKit Auth & Routing, SSO-Implementierung | offen |
| 3 | `BookingGrid.svelte` | offen |

## Dokumentation

- [Datenbank-Architektur](docs/01-datenbank-architektur.md) – Datenmodell,
  Entscheidungen, API-Oberfläche
- [Cross-Login / SSO](docs/02-sso-cross-login.md) – warum ein gemeinsames
  Auth-Projekt und wie der domainübergreifende Wechsel funktioniert

## Datenbank einspielen

```bash
supabase db push          # oder: Migrationen der Reihe nach im SQL-Editor
psql "$DATABASE_URL" -f supabase/seed.sql
```

Danach im Dashboard unter **Settings → API → Exposed schemas** das Schema
`booking` ergänzen.

## Tests

Verhaltenstests gegen ein lokales Postgres (≥ 14), kein Supabase nötig:

```bash
./supabase/tests/run.sh
```

Geprüft werden Preislogik, Doppelbuchungsschutz, Buchungsregeln,
RLS-Sichtbarkeit, Open-Match-Beitritt, anonymer Grid-Zugriff und der
SSO-Handoff.

## Struktur

```
supabase/
  migrations/   9 Migrationen, idempotent, in Reihenfolge ausführbar
  seed.sql      Startdaten Sportcenter Hahn (Platzhalter – bitte anpassen)
  tests/        Verhaltenstests + minimaler Supabase-Stub
docs/           Architekturdokumentation
```
