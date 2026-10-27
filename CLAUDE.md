# Hinweise für Coding-Agenten

Projektanweisungen, Übergaben und Betriebswissen liegen nicht in diesem
Repository, sondern in einer privaten Ablage des Autors. Wer ohne diese Ablage
arbeitet, hält sich an die folgenden Regeln.

## Grundsätze

- Änderungen nur über einen Pull Request auf `main`. Ein Thema pro PR.
- Commits nach [Conventional Commits](https://www.conventionalcommits.org/de/),
  Betreff im Präsens, höchstens 72 Zeichen, auf Deutsch oder Englisch.
- Jede Änderung, die Nutzer:innen bemerken, kommt im selben PR in
  `CHANGELOG.md` unter `[Unreleased]`
  ([Keep a Changelog](https://keepachangelog.com/de/1.1.0/)).
- Neues Verhalten bekommt einen Test, eine Fehlerbehebung zuerst den Test, der
  den Fehler zeigt.
- Keine neuen Abhängigkeiten ohne Rücksprache.
- In dieses Repository gehören keine Zugangsdaten, Hostnamen privater Server,
  lokalen Pfade, Testkonten oder Arbeitsnotizen, auch nicht in
  Commit-Nachrichten, PR-Texten oder Kommentaren. Der Secret-Scan in CI prüft
  das.

## Kommentare

**Kommentare.** Ein Kommentar ist eine Zeile und sagt, warum etwas so ist.
Nicht, was der Code tut, nicht, wie es dazu kam, keine Merksätze, keine
Erklärprosa. So reicht es: „Deploy-Skript statt Portainer-Webhook: auf dem
Zielserver läuft kein Portainer.“ Zwei Zeilen nur, wenn sonst ein Fehler
droht; Vorgeschichte gehört in die Commit-Nachricht. Ein Dateikopf nennt in
einer Zeile, was die Datei ist, dazu höchstens der Aufruf. Der Quelltext ist
zum Veröffentlichen geschrieben: keine Hostnamen, IPs, Server- oder
Proxy-Aufbau, Stack- oder Registry-IDs, Auftragsnummern, Befundkennungen,
Agenten, Namen außer dem Autor, keine wörtlichen Zitate von Entscheidungen,
kein Verweis auf die Werkstatt. Kein `TODO` ohne Issue-Nummer, kein
auskommentierter Code. Wer einen Kommentar anfasst, kürzt ihn auf diese
Regel. Gegenprobe vor jedem Merge: der Prüf-Scan des Repos meldet „Prüfung
ohne Treffer"; wo es einen Quelltext-Export gibt, ist das `node
scripts/quelltext-export/export.mjs HEAD`, sonst gitleaks mit der
Konfiguration der Werkstatt.

## In English

Project instructions, handover notes and operational knowledge are not kept
in this repository but in the author's private notes. Without them, follow
these rules.

- Changes only via a pull request to `main`. One topic per pull request.
- Commits follow [Conventional Commits](https://www.conventionalcommits.org/),
  subject in the present tense, at most 72 characters, in German or English.
- Every change that users notice goes into `CHANGELOG.md` under
  `[Unreleased]` in the same pull request
  ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).
- New behaviour gets a test; a bug fix first gets the test that shows the bug.
- No new dependencies without asking.
- No credentials, private server hostnames, local paths, test accounts or
  work notes in this repository, including commit messages, pull request
  texts and comments. The secret scan in CI checks this.

Comments: a comment is one line and says why something is the way it is.
Not what the code does, not how it came about. Two lines only where a mistake
would otherwise follow; history belongs in the commit message. A file header
names in one line what the file is, plus at most how to call it. No hostnames,
IPs or server details, no `TODO` without an issue number, no commented-out
code.
