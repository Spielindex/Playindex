# Handoff-Endpunkt für padelindex.de / tennisindex.eu

Diese beiden Dateien kommen in die **Partner-App**, nicht in Playindex.
Zusammen sind sie alles, was auf der Gegenseite nötig ist.

```
src/routes/api/zu-playindex/+server.ts   -> holt das Ticket und leitet weiter
```

Konfiguration auf der Partnerseite:

```
PLAYINDEX_BASE_URL="https://playindex.de"
PLAYINDEX_PARTNER_NAME="tennisindex"       # bzw. "padelindex"
PLAYINDEX_PARTNER_SECRET="<dasselbe Secret wie in Playindex>"
```

Im Frontend reicht dann ein normaler Link:

```svelte
<a href="/api/zu-playindex?ziel=/buchen/sportcenter-hahn">Platz buchen</a>
```

Der Nutzer landet eingeloggt im Buchungsgrid. Kein Formular, keine E-Mail.
