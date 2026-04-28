# Backend DLRG Verwaltung

Dieses Backend stellt eine REST-API fuer die Flutter-Anwendung bereit.

## Lokal starten

1. `dart pub get`
2. Serverseitige Environment-Datei anlegen (z. B. `/etc/dlrg-backend.env`)
3. `dart run bin/backend.dart`

Die API laeuft standardmaessig auf Port `8080`.

## Konfiguration (nur Server-Environment)

Unterstuetzte Variablen:

- `PORT` (Default: `8080`)
- `DB_PATH` (Default: `data/dlrg_backend.db`)
- `SERVER_PEPPER` (**Pflicht**, kein Default)
- `ADMIN_USERNAME` (optional, fuer initialen Seed)
- `ADMIN_PASSWORD` (optional, fuer initialen Seed)
- `ENV_FILE` (optional, Default: `/etc/dlrg-backend.env`)

Prioritaet:

1. OS/systemd Environment
2. Datei aus `ENV_FILE` (standard: `/etc/dlrg-backend.env`)
3. Default nur fuer nicht-sensitive Werte (`PORT`, `DB_PATH`)

Hinweis:

- Zugangsdaten und Secrets gehoeren nicht ins Repository.
- Lege die Datei `/etc/dlrg-backend.env` nur auf dem Server an.

Beispiel `/etc/dlrg-backend.env`:

```env
PORT=8080
DB_PATH=/opt/dlrg-backend/data/dlrg_backend.db
SERVER_PEPPER=<langer-zufaelliger-geheimer-wert>
ADMIN_USERNAME=admin
ADMIN_PASSWORD=<starkes-passwort>
```

Beispiel `systemd`-Ausschnitt:

```ini
[Service]
EnvironmentFile=/etc/dlrg-backend.env
WorkingDirectory=/opt/dlrg-backend
ExecStart=/usr/bin/dart run bin/backend.dart
```

## Endpunkte

- `POST /auth/login`
- `GET /roles`
- `POST /admin/users`

## Deployment auf Ionos Ubuntu

1. Dart SDK auf dem Server installieren.
2. Projekt auf den Server kopieren (z. B. nach `/opt/dlrg-verwaltung/backend`).
3. `dart pub get` ausfuehren.
4. Systemd-Service anlegen (z. B. `dlrg-backend.service`) und `PORT=8080` setzen.
5. Reverse Proxy via Nginx auf HTTPS konfigurieren.

Wichtig: Fuer Produktion das JWT-Secret in `lib/src/auth.dart` durch einen sicheren Wert aus einer Umgebungsvariable ersetzen.
