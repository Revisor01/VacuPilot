# Firmware-Kompatibilität

Diese Datei hält fest, welche Version der Roboter-Firmware (Valetudo) mit welcher
VacuPilot-Version getestet ist — und was in neueren Firmware-Releases dazugekommen
ist, das die App noch nicht abdeckt.

**Pflege-Regel:** Bei jedem Release wird hier die getestete Firmware-Version
eingetragen. Wenn ein neues Firmware-Release erscheint, kommt es unter
"Offene Firmware-Neuerungen", bis es in der App abgebildet ist.

## Kompatibilitätsmatrix

| VacuPilot | Build | Datum | Minimum | Getestet gegen | Nachweis |
|---|---|---|---|---|---|
| 1.1.2 | 107 | 2026-10-22 | 2024.06.0 | 2026.10.0 (nach Quelltext) | Kein Gerätetest; Schnittstellen-Abgleich 2026.08.0 → 2026.10.0, neue Anzeigen nur durch Komponententests |
| 1.1.0 | 104 | 2026-10-07 | 2024.06.0 | 2026.08.0 | Praxistest auf Roborock S5 Max (Build 103); Teppich und Karten-Markierungen nur gegen simulierten Roboter, MQTT-Änderung des Hauptzweigs nach Quelltext |
| 1.0.0 | 99 | 2025-12-20 | 2024.06.0 | 2026.02.0 · 2026.05.0 | Live-OTA-Test zweier Roboter (Phase 34, 2026-05-27) |

**Minimum 2024.06.0** ist die dokumentierte Untergrenze (README, STACK.md). Sie ist
nicht per Code-Check erzwungen — die App fragt keine Firmware-Version ab, bevor sie
Endpunkte anspricht, sondern richtet sich nach der Capability-Liste des Roboters.
Ältere Firmware führt darum nicht zu einer klaren Fehlermeldung, sondern zu
fehlenden Funktionen.

### Rückwirkende Einordnung

Die getesteten Versionen sind aus den Projektunterlagen belegbar:

- **2026.05.0 / 2026.02.0** — Live-Test des OTA-Update-Flows gegen zwei reale
  Roboter, Update von 2026.02.0 auf 2026.05.0 erfolgreich (Phase 34, 2026-05-27).
  Das ist der jüngste belegte Praxistest.
- **2026.02.0** — Grundlage der Bonjour-Discovery-Fehlersuche (Phase 32.1, 2026-04-29).
- **2024.06.0** — als Mindestanforderung dokumentiert, seit die Anforderungen
  geschrieben wurden; kein Testprotokoll dazu vorhanden.

Für den Store-Stand v1.0.0 (Build 99, ausgeliefert 2025-12-20) gibt es kein
Testprotokoll gegen eine bestimmte Firmware. Die Angabe oben beschreibt den
Firmware-Stand, gegen den der aktuelle Repo-Code zuletzt lief — nicht den Stand
zum Zeitpunkt der Store-Auslieferung.

## Firmware-Neuerungen seit 2026.05.0

Drei Firmware-Releases sind seit dem Praxistest von 1.0 erschienen. Was davon in
1.1.0 abgedeckt ist, steht jeweils dabei.

### 2026.07.0 (2026-07-23)

**Teppich als Bodenbelag für Räume** — in 1.1.0 umgesetzt.
Räume können zusätzlich als Teppich markiert werden, in drei Abstufungen
(kurzflorig, hochflorig, allgemein). Die App kennt diese Werte jetzt, zeigt sie
an und bietet sie zur Auswahl an. Zusätzlich werden Beläge, die die App noch
nicht kennt, lesbar dargestellt statt weggelassen — vorher blieb ein Raum mit
einem neueren Belag ohne Angabe.

**Karten-Anmerkungen** — in 1.1.0 umgesetzt.
Türschwellen, Vorhänge und Rampen können in der Karte markiert werden, damit der
Roboter sie anders befährt. Die App zeigt sie an, lässt sie einzeichnen und
wieder löschen; angeboten wird nur, was der jeweilige Roboter meldet.
Herstellerabhängig, bisher nur auf einem Teil der Geräte.

Technisch sind sie keine neue Art von Kartenobjekt, sondern drei zusätzliche
Werte im vorhandenen `type`-Feld der Karten-Entitäten: `threshold` und `curtain`
als Linie (zwei Punkte), `ramp` als Viereck (vier Punkte, nicht
achsenparallel). Aufbau, Einheit (cm) und Punktformat sind identisch zu
`virtual_wall` und `no_go_area`. Zum Anzeigen genügt also, diese Werte
mitzuzeichnen — dafür fehlt allerdings die Grundlage, siehe unten.

Zum Setzen dient `PUT /api/v2/robot/capabilities/MapAnnotationsCapability`. Der
Rumpf ist ein reines Array, dessen Punkte hier abweichend als `{x, y}`-Objekte
notiert werden — nicht als flache Zahlenliste wie in der Karte. Der Aufruf
ersetzt immer den kompletten Bestand: Was nicht mitgeschickt wird, ist danach
gelöscht. Ein Lese-Endpunkt existiert nicht; der Stand kommt ausschließlich aus
der Karte. `GET …/MapAnnotationsCapability/properties` liefert, welche der drei
Arten der jeweilige Roboter kann.

**Aufgeräumte Sperrzonen-Oberfläche** — reine Weboberfläche, ohne Auswirkung
auf die App.

### 2026.08.0 (2026-08-03)

**Kamera-Livebild** — neue Funktion, in der App nicht vorhanden.
Roboter mit Kamera können ein Livebild senden, standardmäßig abgeschaltet und
bewusst nur nach ausdrücklicher Freigabe nutzbar. Die App unterstützt das nicht.

### 2026.10.0 (2026-10-18)

Die Release-Notes drehen sich vor allem um neue Geräte (Mova V50 und Z60) und
die neue Root-Infrastruktur. Für die App relevant ist wenig, aber das Wenige
lohnt sich:

**MQTT-Einstellungen ohne Schnittstellen-Schalter** — in 1.1.0 abgefangen.
Jetzt im Release: Die Schalter für Home Assistant, Homie und „Kartendaten
bereitstellen“ entfallen (Commits `5772c9c` und `31bbc50`). Die Firmware löscht
die Felder `interfaces` und `customizations.provideMapData` beim Start aus der
Konfiguration und lehnt sie beim Speichern ab (`additionalProperties: false` →
HTTP 400). 1.1.0 behandelt sie als optional, blendet die Schalter aus und
schickt sie nicht mit. **Wer noch 1.0 nutzt, kann die MQTT-Seite auf
2026.10.0 weder laden noch speichern**; seit 2026-10-08 ist 1.1.1 im Store.

Beim Prüfen aufgefallen: Die App schickte `optionalExposedCapabilities` beim
Speichern nicht zurück; die Firmware setzt das Feld dann auf eine leere Liste.
Seit 1.1.0 wird es unverändert durchgereicht.

**Neue Trockenzeiten der Mopp-Station** — im Hauptzweig nach 1.1.1 umgesetzt.
`MopDockMopDryingTimeControlCapability` kennt zusätzlich `5h` und `quiet`
(leises Trocknen, Mova V50/Z60). Die App zeigte bisher „5H“ und das englische
„Quiet“; jetzt übersetzt. Künftige Stundenwerte (`6h`) erscheinen lesbar als
„6 h“.

**Auflockerer der Walzenmopp-Station** (Mova Z60) — im Hauptzweig nach 1.1.1
umgesetzt. Neues Verbrauchsteil, gemeldet als `brush`/`secondary` in Minuten.
Typ und Unterart gab es schon, nur hatte die App für `secondary` (sowie
`dock`, `wheel`, `detergent`) keine Übersetzung und zeigte „Bürste
(Secondary)“; `all` wird jetzt wie in der Weboberfläche ausgeblendet. Der
Prozentbalken rechnet mit der Annahme 200 h wie bei Seitenbürsten — die
tatsächliche Lebensdauer des Auflockerers ist nicht dokumentiert.

**Mova V50/Z60** — keine neue Schnittstelle. Die Dreame-Klassen mit
Versionszusatz (`…CapabilityV2`) sind Herstellerumsetzungen hinter den
bekannten Fähigkeitsnamen; die App sieht nur die Namen.

Sonst nur Weboberfläche (Analytics-Seite, Bild-im-Bild-Größe), zwei neue
Dreame-Fehlercodes (kommen als Text vom Roboter, keine App-Änderung nötig),
Midea-Stabilität, Speicherbereinigung und Kamera-Livebild-Feinschliff.

Schnittstellen-Abgleich 2026.08.0 → 2026.10.0 (`backend/lib/webserver`,
`entities`, `core`, `res`): außer den beiden Punkten oben und dem
Kamera-Router keine Änderung.

## Abweichungen einzelner Hersteller

### Midea: Teppich-Nummer als Zahl (PR #4)

Gemeldet und behoben von Juli-L (Eureka J15 Pro Ultra, Firmware 2026.10.0):
Die Karte blieb leer. Erkannte Teppiche stehen in der Karte als eigene Entität
(`PolygonMapEntity`, Typ `carpet`), und Midea liefert deren Nummer als Zahl —
`"metaData": {"id": 1}`. Die App erwartete dort Text, wie bei den
Hindernis-IDs, und verwarf daran die ganze Karte. Dreame schickt dieselbe
Nummer als Text (`"1"`). Beides steht schon in 2026.02.0 so im Quelltext;
betroffen war also jede bisherige App-Version, nicht erst die neue Firmware.

Behoben im Hauptzweig nach 1.1.2:

- Die id wird als Text oder Zahl gelesen (Julis Fix aus #4).
- Ein Kartenelement, das die App nicht lesen kann, wird übersprungen und im
  Log vermerkt, statt die ganze Karte zu verwerfen.
- Hindernisse werden am Typ `obstacle` erkannt. Vorher zählte jede Entität mit
  id als Hindernis, bei Dreame also auch die Teppiche.

Die Teppichflächen selbst zeichnet die App nicht; die Weboberfläche tut das.

Nachweis: Komponententests und der simulierte Roboter, der eine Teppichfläche
im Midea-Format liefert. Ein Gegentest auf der J15 steht aus.

## Womit getestet werden kann

Die Testgeräte sind zwei Roborock S5 Max. Das begrenzt, was überhaupt praktisch
prüfbar ist:

- **Bodenbeläge** — nicht prüfbar. Der S5 Max meldet die zugehörige Fähigkeit
  gar nicht erst; sie ist bei Roborock erst ab G10S/S8 vorhanden. Selbst dort
  gäbe es keine Teppich-Werte, sondern nur generic, tile und die beiden
  Holzrichtungen. Teppich existiert bislang ausschließlich bei Dreame.
- **Karten-Anmerkungen** — nicht prüfbar. Nur bei Dreame umgesetzt (Türschwellen
  ab L10s Ultra, zusätzlich Vorhänge und Rampen ab X/L40). Für Roborock gibt es
  keine Umsetzung.
- **Alles Übrige** — prüfbar. Verbindung, Karte, Räume, Zonen, Zeitpläne und der
  Update-Ablauf laufen auf dem S5 Max und decken den Großteil der App ab.

Für die beiden nicht prüfbaren Punkte wäre ein Dreame-Gerät nötig; ein neuerer
Roborock hilft nur beim Bodenbelag und auch dort nicht beim Teppich. Solange
kein solches Gerät vorhanden ist, bleiben beide Punkte nach Code und
Fremdmeldungen umgesetzt statt selbst verifiziert — das ist beim Eintragen in
die Matrix so zu kennzeichnen.

## Was für ein nächstes Release zu tun ist

Die Punkte für 1.1.0 (Gegentest 2026.08.0, unbekannte Bodenbeläge, Teppich,
Karten-Anmerkungen) sind erledigt. Für das nächste Release:

1. **Gegen 2026.10.0 gegentesten** — S5 Max per OTA auf 2026.10.0 bringen,
   dann Verbindung, Karte, Räume, Zonen, Zeitpläne und Update-Ablauf prüfen.
   Wichtigster Einzelpunkt: **MQTT-Seite laden und speichern**. Die Anpassung
   aus 1.1.0 lief bisher nur gegen Quelltext und Tests — 2026.10.0 ist die
   erste Firmware, auf der sie am echten Gerät prüfbar ist.
2. **Neue Trockenzeiten und Verbrauchsteil-Namen** — nur gegen nachgestellte
   Antworten prüfbar; der S5 Max hat keine Mopp-Station.
3. **Karte auf Midea** — die Korrektur aus PR #4 ist nur gegen Tests und den
   simulierten Roboter geprüft. Juli kann sie auf der J15 bestätigen.

Nicht nötig: die Mindestversion anzuheben. Alles, was die App heute anspricht,
gibt es in 2026.10.0 unverändert oder abwärtskompatibel.

## Bewusst nicht geplant

**Kamera-Livebild.** Wird nicht umgesetzt — Entscheidung vom 2026-08-11. Der
Aufwand steht in keinem Verhältnis zum Nutzen: ein Videostrom im MPEG1-Format
über eine Dauerverbindung ist auf iOS ein eigenes Projekt, dazu kommen
Datenschutz- und Store-Fragen. Die Funktion ist auch in der Firmware selbst
bewusst als Ausnahme angelegt, die man aktiv einschalten muss.

Hinzu kommt: Der vorhandene S5 Max hat gar keine Kamera, die Funktion wäre hier
also nicht einmal testbar.
