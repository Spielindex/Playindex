# Schritt 3 · BookingGrid

> Status: implementiert. `npm test` grün (12 SSO + 16 Zeitlogik + Typprüfung),
> `./supabase/tests/run.sh` → 25/25, Cloudflare-Build grün.
> Layout gegen echtes Chromium vermessen (Playwright), nicht nur kompiliert.

## Der Weg zur Buchung

```
/  →  /buchen/sportcenter-hahn        Grid ist sofort da, ohne Login
      ├─ Tap auf freien Slot          Sheet mit Dauer + Preis
      └─ „Buchen"                     fertig
```

Zwei Taps für den Normalfall, drei mit Open-Match-Toggle. Kein Zwischenschritt
für Datum, Platz oder Sportart — das steht alles schon im Grid.

## Aufbau

```
BookingGrid.svelte      Plätze als Spalten, Zeit als Zeile
BookingSheet.svelte     Bottom-Sheet mit Dauer, Open-Match, Preis
lib/utils/zeit.ts       Zeitzonen- und Slot-Logik (16 Tests)
```

Plätze als **Spalten**, nicht als Zeilen: nur so lässt sich der Tag am Stück
lesen und horizontal zwischen den Plätzen wischen. Die Zeitachse klebt links,
die Kopfzeile oben — beim Scrollen bleibt immer klar, welcher Platz und welche
Uhrzeit man gerade ansieht.

## Zustände einer Zelle

| Zustand | Darstellung | Tap |
|---|---|---|
| frei | grün, Uhrzeit sichtbar | öffnet das Sheet |
| offenes Match | orange, „sucht 2" | (Schritt 4: beitreten) |
| deine Buchung | Akzentfarbe, „du" | — |
| belegt | neutralgrau, ohne Angaben | — |
| vergangen / geschlossen | transparent | — |

Belegte Slots zeigen **nie**, wer gebucht hat — das kommt aus
`v_court_availability`, die genau diese Spalten nicht enthält.

## Die vier Dinge, die dabei schiefgingen

Alle vier wurden erst durch Messen im echten Browser sichtbar, nicht durch
Typprüfung oder Kompilieren.

**1. scroll-snap versteckte die erste Spalte.** `scroll-snap-align: start`
richtet die Spalte am Scrollport-Rand aus — und genau dort sitzt die klebende
Zeitachse. Beim Laden sprang der Container auf `scrollLeft: 56` und schob
Padel 1 unter die Zeitspalte. Fix: `scroll-padding-left` in Breite der
Zeitspalte.

**2. Der Header klebte nicht.** `sticky top-0` bezieht sich auf den nächsten
Scrollport. Ohne eigene Höhe scrollte die Seite statt des Containers, und die
Platznamen waren nach unten weg. Fix: `max-h-[70dvh] overflow-auto`.

**3. Tailwind v4 hebt `@theme` aus `@media` heraus.** Ich hatte die
Dark-Mode-Tokens in einem zweiten `@theme` innerhalb einer Media-Query
definiert — Tailwind zieht solche Blöcke unbedingt nach `:root`, wodurch die
dunklen Werte *immer* galten. Die App war im hellen Modus dunkel. Fix: einmal
`@theme` als Basis, Dark-Mode als normale Custom-Property-Overrides.

**4. Nicht existierende Uhrzeiten.** Am 29.03.2026 springt die Uhr von 02:00
auf 03:00. Die Achse erzeugte trotzdem 02:00 und 02:30 — und beide landeten auf
demselben Instant wie 03:00/03:30. Zwei Zellen, ein Zeitpunkt, gegenseitig als
belegt markiert. Fix: Slots, deren Wandzeit nicht zurückkonvertiert, fallen
raus. Der Test dafür stand vor dem Fix.

## Zeitzonen

Alles kommt als UTC aus der Datenbank, gerendert wird die Wandzeit des Clubs.
Der Browser des Spielers ist dabei irrelevant — wer aus dem Urlaub bucht, sieht
dieselben Slots wie jemand vor Ort. `zeit.ts` löst das über `Intl`, ohne
Zusatzbibliothek.

Die Umstellung auf Winterzeit (02:00–03:00 gibt es zweimal) wird bewusst nicht
aufgeteilt: bei Öffnungszeiten ab 07:00 tritt der Fall nie auf, und die Wahrheit
über Doppelbelegung steht ohnehin im `EXCLUDE`-Constraint.

## Heute beginnt jetzt

Wer die App um 20 Uhr öffnet, soll nicht durch zwölf tote Stunden scrollen. Am
laufenden Tag beginnt die Achse deshalb beim aktuellen Slot. Bleiben dadurch
weniger als zwei Slots übrig, zeigt das Grid wieder den ganzen Tag.

Eine rote Linie markiert die aktuelle Uhrzeit; ihr Label klebt beim
horizontalen Scrollen mit.

## Preis

Der Preis kommt bei jeder Änderung frisch aus `booking.price_for_me`. Ihn im
Client nachzurechnen hieße, die Tarifregeln zu duplizieren — und irgendwann
weichen die beiden Ergebnisse voneinander ab. Ein Roundtrip pro Auswahl ist der
bessere Tausch.

`price_for_me` ist neu und ersetzt für Clients `calculate_price`: letztere nimmt
eine beliebige `user_id` entgegen und hätte über den Mitgliederpreis verraten,
welchen Tarif ein fremder Nutzer hat. `anon` und `authenticated` haben darauf
jetzt kein `EXECUTE` mehr.

## Fehlerfälle

Die Action übersetzt nur, geprüft wird in der Datenbank:

| Fall | Reaktion |
|---|---|
| `23P01` (Slot gerade vergeben) | „Bitte wähle einen anderen" + Grid lädt neu |
| nicht angemeldet | Redirect auf `/login?weiter=…`, danach zurück ins Grid |
| Öffnungszeit, Vorlauf, Kontingent | Meldung der Datenbank durchgereicht |

## Zugänglichkeit

Freie Slots sind echte `<button>` mit `aria-label` („Padel 1, 16:00 Uhr,
frei"), belegte tragen ihren Zustand im Label. Das Sheet ist ein
`role="dialog"` mit `aria-modal`, Escape schließt. Meldungen laufen über
`role="alert"` bzw. `role="status"`. `prefers-reduced-motion` schaltet
Übergänge ab.

Offen: ein Fokus-Trap im Sheet und Tastaturnavigation im Raster (Pfeiltasten).

## Was als Nächstes ansteht

1. **Offenem Match beitreten** — die Zelle ist tappbar vorbereitet, RLS und
   Policy stehen (Schritt 1 getestet), es fehlt der Dialog.
2. **Realtime** — Supabase-Subscription auf `bookings`, damit sich das Grid
   ohne Reload aktualisiert.
3. **Mitspieler einladen** beim Buchen (`p_participants` nimmt sie bereits an).
4. **Fokus-Trap und Pfeiltasten-Navigation**.
