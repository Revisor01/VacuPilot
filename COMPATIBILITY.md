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

## Offene Firmware-Neuerungen

Seit dem letzten getesteten Stand (2026.05.0) sind zwei Firmware-Releases
erschienen. Beide sind ungetestet.

### 2026.07.0 (2026-07-23)

**Teppich als Bodenbelag für Räume** — betrifft die App direkt.
Räume können jetzt zusätzlich als Teppich markiert werden, in drei Abstufungen
(kurzflorig, hochflorig, allgemein). VacuPilot kennt bisher nur die fünf Werte
generic, tile, wood, wood_horizontal und wood_vertical. Ein Teppich-Wert wird
weder angezeigt noch als Auswahl angeboten. Absturzgefahr besteht nicht — das
Material wird als freier Text gelesen und nur für die Anzeige gedeutet — aber ein
Raum, der am Roboter als Teppich gesetzt ist, erscheint in der App ohne Belag.

**Karten-Anmerkungen** — neue Funktion, in der App nicht vorhanden.
Türschwellen, Vorhänge und Rampen können in der Karte markiert werden, damit der
Roboter sie anders befährt. Die App zeigt diese Markierungen weder an noch lässt
sie sich anlegen. Herstellerabhängig, bisher nur auf einem Teil der Geräte.

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
4. **Karten-Anmerkungen** — größeres Vorhaben (Kartendarstellung und
   Bearbeitung) und hier ebenfalls nicht am Gerät prüfbar. Lohnt eine eigene
   Planungsphase, sobald ein passender Roboter zur Verfügung steht.

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
