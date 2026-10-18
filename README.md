# Rebellion — versione digitale

Adattamento digitale non ufficiale, per uso personale, di **Star Wars: Rebellion** (Corey Konieczka,
Fantasy Flight Games) con l'espansione **L'Ascesa dell'Impero**. Fatto con Godot 4.7, si gioca nel
browser: **https://tannoiser2.github.io/Rebellion/**

## Cosa c'è

- **Gioco base + L'Ascesa dell'Impero**: tutte le missioni, carte azione, obiettivi e carte tattica
  dei due set; i nuovi leader e le nuove unità (U-Wing, Avanguardia Ribelle, Fregata Nebulon-B,
  Torretta Golan Arms, TIE Striker, Carro d'Assalto, Bunker Scudo, Interdictor).
- Opzioni dell'espansione nel menu: mazzi di missioni (base o «Ascesa», con il simbolo di Vader),
  unità iniziali (base o «Ascesa»), combattimento **base** o **cinematografico** (tattiche avanzate).
- **Tabellone 3D** con le miniature del modulo di Tabletop Simulator, sagome dei leader, segnalini
  di fedeltà, sabotaggio, distruzione, coda di costruzione, tempo e reputazione. Vista 2D dall'alto.
- **Avversario IA** per l'una o l'altra fazione (tre livelli), oppure due persone sullo stesso
  dispositivo (una schermata nasconde i segreti fra un turno e l'altro), oppure IA contro IA.
- **Gioco online** con Firebase: stanza con codice di 4 lettere, una fazione per dispositivo; chi
  si disconnette può rientrare con lo stesso codice (nel frattempo gioca l'IA).
- Carte in italiano: per il gioco base le scansioni italiane; le carte dell'Ascesa dell'Impero
  hanno l'immagine originale inglese e, passandoci sopra col mouse, la **traduzione italiana**
  accanto (traduzione fatta per questa versione).
- Musica ed effetti sonori originali, sintetizzati (`tools/sintetizza_audio.py`).

## Comandi

Trascina per ruotare il tabellone, rotella o pizzico per lo zoom, tasto destro (o Maiusc+trascina)
per spostarlo, doppio clic per rimettere la visuale. Clic su un sistema per vederne il dettaglio.
I sistemi da scegliere si illuminano. «Scelta automatica» lascia decidere all'IA. F11 schermo intero.

## Struttura

- `scripts/core/` — il motore: `state.gd` (stato), `engine.gd` (fasi, movimento, costruzione),
  `cards.gd` (missioni, azioni, obiettivi), `combat.gd` (combattimento base),
  `combat_cine.gd` (combattimento cinematografico), `ai.gd` (IA).
- `scripts/ui/` — menu, vista di gioco, tabellone 3D, regole in breve, suoni.
- `scripts/net/` — Firebase (radice `rebellion/rooms`) e partita online in lockstep: viaggiano
  solo le scelte, ogni dispositivo ricalcola la stessa partita con lo stesso seme.
- `tools/` — preparazione degli asset dal modulo TTS e dalle scansioni, testi delle carte,
  sintesi dell'audio, grafica dell'icona.
- `tests/sim.gd` — partite IA contro IA senza grafica:
  `godot --headless --path . --script tests/sim.gd -- 10 1 1 0` (partite, seme, Ascesa, cinematografico).

## Licenze

Codice: per uso personale. Font Orbitron, Exo 2 e Share Tech Mono con licenza SIL OFL
(`assets/fonts/OFL-*.txt`). Star Wars: Rebellion © Fantasy Flight Games / Asmodee;
Star Wars © Lucasfilm Ltd. Immagini delle carte e miniature dal modulo TTS e dalle scansioni
della propria copia del gioco.
