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

Ein Kommentar sagt, warum etwas so ist, nicht was der Code tut oder wie es
früher war. Höchstens drei Zeilen; was mehr braucht, gehört in die
Commit-Nachricht oder nach `docs/`. Keine Hostnamen, IPs oder Serverdetails,
kein `TODO` ohne Issue-Nummer, kein auskommentierter Code.

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

Comments: a comment says why something is the way it is, not what the code
does or how it used to be. At most three lines; anything longer belongs in
the commit message or in `docs/`. No hostnames, IPs or server details, no
`TODO` without an issue number, no commented-out code.
