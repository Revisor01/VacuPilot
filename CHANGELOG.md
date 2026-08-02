# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog 1.1.0](https://keepachangelog.com/de/1.1.0/),
dieses Projekt folgt [Semantic Versioning 2.0.0](https://semver.org/lang/de/).

> **Hinweis zur Versionierung:** Die App-Store-Version ist die maßgebliche Version
> (`MARKETING_VERSION` in `ValetudoApp/project.yml`). Die intern im Ordner
> `.planning/` geführten Milestones (v2.0.0–v4.0.1) sind **Entwicklungszyklen**
> des GSD-Workflows und keine ausgelieferten Versionen — sie sind unten den
> jeweiligen Store-Builds zugeordnet.

## [Unreleased]

### Geändert

- Screenshot-Generator (`ValetudoApp/AppStore/screenshots`): Export rendert die
  Slides jetzt on-demand über `createRoot` statt 27 permanent versteckter
  Vollformat-Nodes im DOM zu halten. Vorschau-Kacheln nutzen
  `content-visibility: auto` und `contain`, wodurch die Seite auf Rechnern mit
  wenig RAM nicht mehr einfriert.
- Build-Nummer im Repo auf den tatsächlich ausgelieferten Stand gezogen
  (`CURRENT_PROJECT_VERSION` 97 → 99), `MARKETING_VERSION` auf `1.0.0`
  normalisiert.

### Entfernt

- Layouts `mock-podest` und `mock-edge` aus dem Screenshot-Generator.
- Altlasten aus dem Repo-Root: `SUPPORT-AUFTRAG.md` (umgesetzter
  Implementierungsauftrag — `SupportManager.swift` existiert), loses `AppIcon.png`
  (liegt im Asset-Katalog), XCResult-Archiv von Build 11, `.playwright-mcp/`-Logs.

## [1.0.0] — 2025-12-20

Erstveröffentlichung im App Store (Build 99, Stand 2026-06-10).

Native iOS-App zur Steuerung von Saugrobotern im lokalen Netzwerk über die
REST-API v2 — ohne Cloud, ohne Tracking, ohne Konto.

### Hinzugefügt

- **Roboter-Verwaltung:** Hinzufügen, Bearbeiten und Entfernen von Robotern per
  LAN; Credentials sicher im iOS-Keychain.
- **Automatische Erkennung:** mDNS/Bonjour-Discovery (`_valetudo._tcp`) mit
  parallelem IP-Scan als Fallback.
- **Live-Karte:** Interaktive Kartenansicht mit Zoom/Pan, Raumdarstellung, Zonen
  und Echtzeit-Updates via Server-Sent Events (Polling als Fallback).
- **Reinigung:** Raumauswahl mit frei wählbarer Reihenfolge, Wiederholungen
  (1×/2×/3×), Zonenreinigung, GoTo-Presets sowie Start/Stop/Pause/Home.
- **Kartenbearbeitung:** Räume teilen, zusammenführen und benennen; virtuelle
  Wände und Sperrzonen.
- **Timer:** Reinigungszeitpläne erstellen, bearbeiten und löschen.
- **Manuelle Steuerung:** Touchpad-Steuerung mit High-Resolution-Velocity.
- **Verbrauchsmaterial:** Reststandsanzeige inklusive Benachrichtigung bei
  niedrigem Stand.
- **OTA-Updates:** Geführter Update-Prozess mit Fortschrittsanzeige,
  Vollbild-Sperre während Apply/Reboot und automatischer Neustart-Erkennung.
- **Siri & Kurzbefehle:** Sprachsteuerung über App Intents.
- **Benachrichtigungen:** Lokale Hinweise zu fertiger Reinigung, Fehlern und
  Verbrauchsmaterial; Hintergrund-Überwachung via `BGAppRefreshTask`.
- **Weiteres:** Onboarding, Demo-Modus, Dark Mode, Karten-Cache für den
  Offline-Fall, Unterstützer-Funktion via StoreKit 2.
- **Lokalisierung:** Deutsch, Englisch und Französisch (FR aus der Community).

### Interne Entwicklungszyklen bis zu diesem Release

- **v2.0.0 — Update Process Hardening** (2026-04-01): `UpdatePhase`-State-Machine
  als Single Source of Truth, Re-Entrancy-Guards, Fehler-States, Idle-Timer und
  Background-Task-Schutz während des Apply-Vorgangs.
- **v2.1.0 — Architecture & Background** (2026-04-02): Migration auf
  `@Observable`, `BackgroundMonitorService`, `MapCacheService`.
- **v2.2.0 — Room Interaction & Cleaning Order** (2026-04-04): Raumauswahl von
  `Set` auf geordnetes Array umgestellt, damit die Auswahlreihenfolge der
  Reinigungsreihenfolge entspricht.
- **v3.0.0 — Quality, Performance & Hardening** (2026-04-05): Zentraler
  `ErrorRouter`, durchgängiges `os.Logger`-Logging statt `print()`, vereinheitlichte
  Kartengeometrie (`MapGeometry.swift`), O(1)-Hit-Testing für Raum-Taps,
  vorgerenderte Karten-Ebenen auf Hintergrund-Thread, Aufspaltung großer Views
  (u. a. `RobotDetailView` 1210 → 143 Zeilen), XCTest-Target mit Unit-Tests.
- **v4.0.0 — App Store Release** (2026-04-29): Store-Listing in DE/EN/FR,
  Screenshot-Generator, Bonjour-Hostname-Korrektur.
- **v4.0.1 — OTA Hotfix** (2026-05-27): Install-Button, Auto-Refresh nach Reboot,
  Warnung beim Verlassen während eines Updates.

### Behoben (Auswahl, bis Build 99)

- Karte fror beim Öffnen ein — RLE-Dekompression und `segmentInfos`-Berechnung
  vollständig vom Main-Thread verlagert.
- Endlose Re-Render-Schleife in `MapContentView`.
- SSE-Reconnects mit exponentiellem Backoff und Wiederholungslimit, um
  Actor-Starvation zu verhindern.
- Roboter wurden fälschlich als „nicht erreichbar“ angezeigt.
- Rundungsfehler bei der Pixel-Koordinaten-Umrechnung (Zonen, GoTo, Raum-Teilung).
- Links/Rechts-Steuerung in der manuellen Steuerung war vertauscht.
- 401-Leak beim Navigieren zwischen Robotern; stille Update-Prüfung.
- Verlorene SSL-Einstellungen beim Speichern eines Roboters.

### Sicherheit

- Zugangsdaten ausschließlich im iOS-Keychain, nie in `UserDefaults`.
- Warnbanner und Lock-Icon bei unverschlüsselten HTTP-Verbindungen und
  aktiviertem SSL-Bypass.

### App-Review-Anpassungen

- Umbenennung von „ValetudiOS“ zu **VacuPilot** (App-Store-Guidelines 5.2.5 und
  5.2.1: „iOS“ im Namen unzulässig, fremder Projektname nicht autorisiert).
- Nennungen der fremden Marke in App und Store-Texten auf beschreibende
  Kompatibilitätshinweise reduziert (Guideline 5.2.1).
- App auf iPhone-only umgestellt; `ITSAppUsesNonExemptEncryption` in
  `project.yml` verankert.

[Unreleased]: https://github.com/Revisor01/VacuPilot/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Revisor01/VacuPilot/releases/tag/v1.0.0
