<p align="center">
  <img src="ValetudoApp/ValetudoApp/Media.xcassets/AppIcon.appiconset/Untitled-iOS-Default-1024x1024@1x.png" alt="VacuPilot" width="128" height="128">
</p>

<h1 align="center">VacuPilot</h1>

<p align="center">
  Die iOS-App für Saugroboter mit quelloffener Firmware und lokaler REST-API.<br>
  Volle Kontrolle. Keine Cloud. Kein Tracking. Dein Roboter, dein Netz, deine Daten.
</p>

<p align="center">
  <a href="README.md">English</a> · <b>Deutsch</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Plattform-iOS%2017%2B-blue?logo=apple" alt="Plattform">
  <img src="https://img.shields.io/itunes/v/6756815432?label=App%20Store&color=green" alt="Version im App Store">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Abh%C3%A4ngigkeiten-keine-brightgreen" alt="Abhängigkeiten">
  <img src="https://img.shields.io/github/license/Revisor01/VacuPilot" alt="Lizenz">
</p>

## Worum es geht

Viele Saugroboter lassen sich mit einer quelloffenen Firmware betreiben, die
die Cloud des Herstellers durch eine lokale REST-API auf dem Roboter ersetzt.
Das ist gut für die Privatsphäre, aber die Weboberfläche des Roboters ist auf
dem Handy unhandlich.

VacuPilot ist eine iPhone-App für genau diese Roboter. Sie spricht direkt im
eigenen Netz mit dem Roboter — kein Konto, keine Cloud, kein Server
dazwischen. Zugangsdaten bleiben im Schlüsselbund des Geräts.

## Funktionen

### Steuerung
- **Mehrere Roboter** — alle Roboter in einer App
- **Status in Echtzeit** — Akku, Reinigungsstand und Statistik live über Server-Sent Events
- **Volle Kontrolle** — starten, stoppen, pausieren, zurück zur Station
- **Manuelle Steuerung** — fahren wie mit einem Joystick, fein aufgelöst
- **Saugstärke und Wassermenge** — Stufen je Reinigung einstellen
- **Nicht stören** — Ruhezeiten festlegen

### Karte und Reinigung
- **Interaktive Live-Karte** — zoomen, verschieben, Position des Roboters in Echtzeit
- **Raumreinigung** — Räume direkt auf der Karte antippen
- **Reihenfolge** — ausgewählte Räume zeigen nummeriert, in welcher Folge gereinigt wird
- **Mehrere Durchgänge** — Anzahl je Reinigung festlegen
- **Zonenreinigung** — eigene Zonen auf die Karte zeichnen
- **Sperrbereiche** — No-Go-Zonen, Wischverbotszonen und virtuelle Wände
- **Zielorte** — Lieblingsorte speichern und den Roboter hinschicken
- **Kartenstände** — Karten sichern und wiederherstellen

### Überwachung und Mitteilungen
- **Verschleißteile** — Filter, Bürsten und Sensoren mit Warnung bei niedrigem Stand
- **Mitteilungen** — Reinigung fertig, Roboter steckt fest, Fehler, Verschleiß
- **Überwachung im Hintergrund** — regelmäßige Statusabfrage auch bei geschlossener App
- **Karte ohne Netz** — Karten werden lokal zwischengespeichert

### Einstellungen am Roboter
- **Firmware-Updates** — prüfen, laden und einspielen, mit Vollbild-Schutz während des Vorgangs
- **Zeitpläne** — Reinigungszeiten anlegen und verwalten
- **Sprachpakete** — Sprachen durchsehen und wechseln
- **MQTT** — alle Einstellungen für den Broker (Home Assistant / Homie)
- **NTP** — Zeitserver
- **WLAN** — Signalstärke, Netze suchen, WLAN einrichten
- **Quirks** — modellspezifische Einstellungen
- **Teppichmodus** — automatische Saugkraft auf Teppich ein- und ausschalten
- **Absaugstation** — Dauer und Verhalten der automatischen Entleerung
- **Geräteinfo** — Hardware, Firmware-Version, Systemzustand

### App
- **Automatische Suche** — findet Roboter über Bonjour (mDNS) und IP-Scan
- **SSL/TLS** — HTTPS-Verbindungen, selbst signierte Zertifikate auf Wunsch
- **Verbindungen mit Verstand** — lokale Roboter werden außerhalb des WLANs übersprungen, unerreichbare pausiert
- **Siri-Kurzbefehle** — Sprachsteuerung für häufige Aktionen
- **Dunkelmodus** — vollständig
- **Sprachen** — Englisch, Deutsch, Französisch
- **VoiceOver** — vollständig barrierefrei
- **Keine Abhängigkeiten** — keine fremden SDKs, kein Lieferkettenrisiko
- **DSGVO-konform** — alle Daten bleiben auf dem Gerät

## Installation

**[Im App Store laden »](https://apps.apple.com/app/id6756815432)** ·
**[TestFlight-Beta »](https://testflight.apple.com/join/N11Ncb1D)**

Nötig sind iOS 17 oder neuer und ein Roboter mit kompatibler quelloffener
Firmware (2024.06.0 oder neuer), der im eigenen Netz oder per VPN erreichbar
ist.

### Erste Schritte

1. App öffnen
2. Auf die Suche tippen, um Roboter automatisch zu finden, oder einen per IP bzw. Hostname von Hand anlegen
3. Bei Bedarf die Anmeldung einschalten, wenn sie in der Firmware des Roboters eingerichtet ist

## Kompatibilität

In [COMPATIBILITY.md](COMPATIBILITY.md) (englisch) steht, gegen welche
Firmware-Versionen jede App-Version geprüft wurde und welche neueren
Funktionen der Firmware noch fehlen.

### Unterstützte Roboter

VacuPilot läuft mit allen Saugrobotern, deren quelloffene Firmware eine lokale REST-API bereitstellt:

- **Roborock** — S5, S5 Max, S6, S7, Q Revo und weitere
- **Dreame** — L10 Pro, Z10 Pro, L20 Ultra, X40 Ultra und weitere
- **Xiaomi / Viomi** — verschiedene Modelle
- und viele mehr

## Versionen

Was sich wann geändert hat, steht in [CHANGELOG.md](CHANGELOG.md) — nach
[Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Die
[Releases](https://github.com/Revisor01/VacuPilot/releases) fassen jede Version
zusammen.

## Selbst bauen

```bash
git clone https://github.com/Revisor01/VacuPilot.git
cd VacuPilot
open ValetudoApp/ValetudoApp.xcodeproj
```

Xcode mit dem SDK für iOS 17 oder neuer. In den Signierungs-Einstellungen das
eigene Team eintragen, dann auf Gerät oder Simulator starten. Es gibt keine
fremden Abhängigkeiten zu installieren. `tools/simulierter-roboter.py` stellt
einen simulierten Roboter bereit, zum Testen ohne Hardware.

## Aufbau

```
VacuPilot
├── Models/          — Codable-Modelle der API, RobotConfig
├── Services/        — ValetudoAPI, RobotManager, SSEConnectionManager,
│                      UpdateService, MapCacheService, BackgroundMonitorService,
│                      NotificationService, KeychainStore, NetworkScanner
├── ViewModels/      — MapViewModel, RobotDetailViewModel, RobotSettingsViewModel
├── Views/           — SwiftUI-Ansichten nach Funktion
│   ├── Detail/      — Abschnitte der Roboteransicht
│   ├── Settings/    — Abschnitte der Robotereinstellungen
│   └── Map/         — Kartenebenen, Zeichnen, Bedienelemente
└── Tests/           — 151 Unit-Tests, laufen bei jedem Pull Request (Modelle, Geometrie, Zustände, Zwischenspeicher)
```

**Worauf es beim Bauen ankommt:**
- Reines SwiftUI mit Swift 5.9, keine UIKit-Hüllen (außer der Vollbildsperre beim Update)
- Keine fremden Pakete
- MVVM mit @Observable (iOS 17+)
- SSE-Verbindungen über Actors
- Die Oberfläche richtet sich nach den Fähigkeiten — eine Funktion erscheint nur, wenn der Roboter sie kann

## Mitmachen

Fehlermeldungen und Vorschläge sind willkommen — gern als
[Issue](https://github.com/Revisor01/VacuPilot/issues), auf Deutsch oder
Englisch. Sicherheitslücken bitte vertraulich melden, wie in
[SECURITY.md](SECURITY.md) beschrieben. Pull Requests laufen durch Tests und
einen Secret-Scan; siehe [CONTRIBUTING.md](CONTRIBUTING.md).

## Datenschutz

VacuPilot sammelt nichts: keine Analyse, keine Werbung, keine Cloud-Dienste,
keine fremden SDKs. Die App verbindet sich nur mit den Robotern, die man
selbst einträgt. Adressen der Roboter, optionale Zugangsdaten, Einstellungen,
gespeicherte Orte und der Kartenspeicher bleiben auf dem Gerät (Zugangsdaten
im Schlüsselbund) und verschwinden mit der App.

Vollständige Erklärung:
[simonluthe.de/apps/vacupilot/datenschutz](https://simonluthe.de/apps/vacupilot/datenschutz/)

## Lizenz

VacuPilot steht unter der
[GNU Affero General Public License v3.0](LICENSE). Wer VacuPilot verändert und
anderen zur Verfügung stellt, auch als Webdienst, legt seinen Quelltext unter
derselben Lizenz offen. Für
Beiträge gilt [CONTRIBUTING.md](CONTRIBUTING.md). Maßgeblich ist der Text in
[LICENSE](LICENSE).

Die Fassungen im App Store verteilt der Urheber als Rechteinhaber selbst.

## Hinweis

VacuPilot ist eine unabhängige Begleit-App. Sie spricht mit Saugrobotern, die
eine kompatible quelloffene Firmware nutzen, ausschließlich über deren
dokumentierte lokale REST-API. Sie gehört zu keinem Firmware-Projekt, wird von
keinem unterstützt und enthält keinen fremden Quelltext, keine fremden Grafiken
und keine fremden Marken.

## Kontakt

Simon Luthe · [mail@simonluthe.de](mailto:mail@simonluthe.de) ·
[simonluthe.de](https://simonluthe.de)
