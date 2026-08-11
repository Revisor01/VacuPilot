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
| 1.1.0 | 100 | 2026-08-12 | 2024.06.0 | noch offen | Umsetzung nach Firmware-Quelltext und Schnittstellen-Doku von 2026.08.0; Praxistest steht aus |
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

Zwei Firmware-Releases sind seit dem letzten Praxistest erschienen. Was davon in
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

Nach Wichtigkeit, unter Berücksichtigung dessen, was hier prüfbar ist:

1. **Gegen 2026.08.0 gegentesten** — auf dem vorhandenen S5 Max: Verbindung,
   Karte, Räume, Zonen, Zeitpläne, Update-Ablauf. Ergebnis in die Matrix
   eintragen. Der einzige Punkt, der vollständig selbst verifizierbar ist, und
   damit der erste.
2. **Unbekannte Bodenbeläge abfangen** — statt einen unbekannten Wert
   wegzulassen, ihn neutral darstellen. Wirkt für jeden künftigen neuen Wert,
   nicht nur für Teppich, und ist ohne passendes Gerät prüfbar, indem eine
   Antwort mit unbekanntem Material nachgestellt wird.
3. **Teppich-Böden ergänzen** — die drei Teppich-Werte in Anzeige und Auswahl
   aufnehmen, inklusive Symbol und Übersetzungen. Kleiner Eingriff, aber ohne
   Dreame-Gerät nur gegen nachgestellte Antworten prüfbar, nicht am echten
   Roboter. Nach Punkt 2 einsortiert, weil dieser den Schaden bereits abfängt.
4. **Karten-Anmerkungen** — eigene Planungsphase. Ohne Dreame-Gerät nicht am
   Roboter prüfbar, wohl aber gegen einen nachgestellten Server: Die App spricht
   nur HTTP, und das Format ist vollständig dokumentiert (siehe oben). Ein
   Server, der eine Karte mit den drei Werten ausliefert und den PUT annimmt,
   reicht für Entwicklung und Prüfung der Darstellung.

   Zum Anknüpfen ist einiges da: Sperrzonen und virtuelle Wände werden bereits
   gezeichnet und lassen sich anlegen und löschen. Sie kommen allerdings aus
   einem eigenen Abruf der Sperrzonen und nicht aus den Karten-Entitäten;
   Anmerkungen kämen dagegen mit der Karte. Die Darstellung kann sich an den
   vorhandenen Linien und Flächen orientieren, die Datenherkunft ist eine
   andere.

Nicht nötig: die Mindestversion anzuheben. Alles, was die App heute anspricht,
gibt es in 2026.08.0 unverändert.

## Bewusst nicht geplant

**Kamera-Livebild.** Wird nicht umgesetzt — Entscheidung vom 2026-08-11. Der
Aufwand steht in keinem Verhältnis zum Nutzen: ein Videostrom im MPEG1-Format
über eine Dauerverbindung ist auf iOS ein eigenes Projekt, dazu kommen
Datenschutz- und Store-Fragen. Die Funktion ist auch in der Firmware selbst
bewusst als Ausnahme angelegt, die man aktiv einschalten muss.

Hinzu kommt: Der vorhandene S5 Max hat gar keine Kamera, die Funktion wäre hier
also nicht einmal testbar.
