# PokerFection

Learn five games against bots, with a coach that works out the best move on
your own device: No-Limit Hold'em, Gomoku, Big Two, Fight the Landlord and
Blackjack. Play them alone, or online with friends in a room anyone can
watch. In English, Spanish and Chinese, on Windows, Android, iOS and the web.

**Play in your browser:** https://williamszc380.github.io/PokerFection/

## The games

Home is a game picker, plus Settings and Multiplayer. Each game's tile opens
its own menu, with **Play** and its **Guides** (the rules, how to read the
table, and the coach).

- **Hold'em:** No-Limit Hold'em for 2 to 8 players. In GTO Training
  (Simple or Advanced), every decision is scored against a
  game-theory-optimal answer, solved on your own device; the Preflop Charts
  show GTO ranges at every table size. The coach is labelled **GTO**.
- **Gomoku:** five in a row on a 15×15 or 19×19 board, Freestyle (five or
  more wins) by default, with Standard (exactly five) and Renju. The coach,
  **Best move**, searches exactly (threat-space search for forced wins, then
  alpha-beta), and the board marks its top 4 moves, the best brightest.
- **Big Two:** 2 to 4 players (2 by default), with the Standard, Hong Kong,
  Taiwan and Pusoy Dos rules and their options. Who starts is shown at each
  deal: the 3♦'s holder with 3 or 4 players; with 2, cards are called from
  the bottom up and only the starter's lowest card is shown. The coach is
  labelled **GTO**.
- **Fight the Landlord** (Dou Dizhu): three players, an auction for the
  landlord, who takes the three kitty cards and plays against the two
  peasants. A card dealt face up shows who bids first. The coach is
  labelled **GTO**.
- **Blackjack:** against the dealer, with the Standard, Vegas Strip,
  Downtown, Atlantic City, European and Single deck rules. Solo, it is one
  player betting 1 a round: a strategy trainer, with no bankroll. The coach,
  **Basic strategy**, works out exact expected values, also with the count
  (running and true count).

The card games' coaches play like poker's solvers, with no trained AI and
nothing downloaded: they guess the hidden hands that fit what has been
played, search each guess, and solve exactly near the end. A card everyone
has seen that is still in a hand (Big Two's starting card, Fight the
Landlord's face-up card, the kitty in the landlord's hand) shows face up in
its holder's seat for everyone, with an eye in its corner ("Everyone can see
this card" on hover, or a long press); the coaches and bots treat it as known.

### Playing alone

- **Training or Free Play**, chosen before the game: in Training each move
  is graded against the coach (Best, Good, Inaccuracy, Mistake, Blunder) and
  scored from 0 to 100; Free Play has no grades. **Level** sets how well the
  bots play (Easy, Medium, Hard).
- **The coach** is off until you turn it on: it lists the best moves and what
  each is worth. One click on a row picks that move, a double click plays
  it, and Pass is always listed. Play never waits for it: its answers and
  the grades come in when they are ready.
- **Big Two and Fight the Landlord:** the hand is fanned (drag to reorder,
  or sort by Rank or Suit), played cards pile up in the middle (tap the pile
  for the history), and a match is played to a target score (**Play to**, optionally scaled
  with the players). Training can show the bots' cards, and tapping an
  opponent shows what they may hold.
- **Last game:** the most recent game of each, saved after every move, to
  look back through move by move.

## Running and building

- Windows: `./run` (or `run.cmd` in cmd and PowerShell) starts the game
  with hot reload: it picks Flutter's device for this computer (Windows,
  macOS or Linux), and takes Flutter from `FLUTTER_ROOT`, else
  `~/dev/flutter`, else the PATH. `./run -h` shows its options:
  `./run --profile 2` starts another copy with its own settings and name
  online, to play against yourself, and any other option goes to
  `flutter run` (`./run --release`). Plain `flutter run -d windows` works
  too.
- Android and iOS: `flutter run` with the phone connected. The apps play
  sideways on phones.
- Web: `dart run tool/build_web.dart` builds the site into `build/web`.
- Tests: `flutter test`; `dart analyze lib test tool integration_test bin`.

The web build is the app plus two Web Workers, which `flutter build web`
leaves out: the poker solvers' (`lib/solver_worker.dart`) and the other
games' coaches and bots (`lib/game_worker.dart`). Without them the site
still works, but solving and coaching freeze the page. Each worker is
compiled to WebAssembly, which solves 1.1 to 1.6 times faster, and to
JavaScript for browsers that can't run that (no WasmGC);
`dart run tool/worker_bench.dart` times the solvers' in Edge or Chrome, and
`dart run tool/games/game_worker_check.dart` checks that every game job
gives the same answer natively, in JavaScript and in WebAssembly ("All the
same"). Every push to `main` publishes the site
(`.github/workflows/website.yml`).

Each game has its timing tools in `tool/games/` (bot matches and the
coach's time per move: `gomoku_match.dart`, `big_two_match.dart`,
`ddz_match.dart`, `blackjack_match.dart`; the jobs from a cold start:
`*_cold.dart`); `dart run tool/speed_bench.dart` times the poker solves.
Run timing tools one at a time.

The version in Home's bottom-right corner is pubspec.yaml's first two
numbers (2.0, set by hand) and the commit count, with a "+" for uncommitted
changes: "2.0.11+" (`tool/build_label.dart`; a build without `./run` or the
website's build shows "dev"). Tapping it opens About: the version, the
build, the author (Williams Zhang Cen) and the games.

## Drills

Drills are off for now, in every game: the code stays, and they come back by
uncommenting the places marked "Drills are off for now" (all but the count of
due spots on the Drills button: its note in `lib/src/ui/games.dart` says what
it needs). When on:

Every Mistake or Blunder in solo GTO Training (Simple or Advanced) is saved
as a spot: the whole hand up to that decision (table, stacks, every player's
cards, the board and the betting). **Drills** on Hold'em's menu shows how many
are due and deals them again, the most overdue first (Blunders first when
equal): the same hand is replayed to the decision, GTO's answer is solved
again, and the play is graded like Simple training (Show GTO waits until it
is played). Spaced repetition, in real time: a new mistake is first due after
10 min; played right (Good or better) it comes back after 1 h, 1 day, 3 days,
1 week, then about 2.5 times longer each time; played wrong (or the same
mistake again in training), after 10 min. Up to 256 spots are kept (when full,
the best learned go first), in `drills.json` next to the settings (local
storage in the browser). With nothing due, Drills deals random hands at random
tables (2 to 8 players, any position, 10 to 200 BB), and their mistakes join
the drills; ☰ > Saved Spots lists every spot with its next review.

## Playing online

Online play (Home: **Multiplayer**) needs no game server of our
own: **Create Room** runs the game server inside the app of whoever creates
the room (Windows, Android or iOS), on port 47474 (or one of the next few when
it is taken), and the host's app joins it like everyone else. The room lasts
until the host closes it (Close Room, or closing the app).

Rooms are for watching as much as playing:

- **Everyone enters as a spectator**, the host too. The room stays beside
  every screen (docked on the right, a slim rail on a sideways phone, a bar
  on an upright one), so people can go anywhere in the app meanwhile. It
  holds up to 16 people when a PC hosts, 8 on a phone or in a browser.
- **The host picks the game the usual way**, from Home and its menu: any of
  the five. Its setup is the room's, and everyone follows to its table.
- **The seats are on the table:** a tap on an empty seat takes it, the host
  adds bots (the host's device plays them), and a person who joins a game
  full of bots takes a bot's seat. Start and End game are the host's.
- **Spectators see every person's cards**; the bots' only when the host
  turns on **Spectators see bots' cards**. Nobody seated sees another's
  cards (but a card everyone has seen, with its eye).
- **The coach** is there for spectators, off until they turn it on, worked
  out on their own device (the host never sends solves); "—" for a hand
  hidden from them.
- **Away:** when a player's time runs out or they are away, the room plays
  a simple move for them (in Hold'em, check or fold), and the game goes on.

Getting in, and staying in:

- **Same Wi-Fi:** friends join with the room code alone (the app finds the
  room on the network), or with the invite. Works without internet.
- **From anywhere:** the same code or invite. The host takes the room's code
  as its name at a free public meeting service (PeerJS's server; public
  Google and Cloudflare STUN), which only introduces the devices; the game
  then goes device to device over an encrypted WebRTC data channel
  (flutter_webrtc). The room shows "Internet: connecting… / ready / not
  available" with a short reason. There is no relay: when two networks
  can't connect directly (often mobile data), the guest is told to try
  another network or the same Wi-Fi. If the router lets the app open the
  port by itself (UPnP), it does so silently, and invites carry that public
  address too, as a second way in.
- **Invite:** a link that opens the app with every way in to try: the
  host's local addresses, then `peer:CODE` (the room through the meeting
  service), then the router's public address when open.
- **Browser players** press **Play in this browser** on the invite's page:
  the website opens at the room (`?code=ABCDE&server=peer:ABCDE`) and
  connects straight to the host through the meeting service (WebRTC works
  from the https site). When the host's app serves the browser version
  (Windows), the page also links to the host's own copy at
  `http://<host address>:47474/` for the same Wi-Fi (no internet needed);
  an invite from an older app (no `peer:` entry) links only there.
- **Hosting in a browser:** Create Room works on the website too (when the
  browser has WebRTC): the room runs in the tab (the same room code, in
  plain Dart), the page's own player joins it in memory, and everyone
  comes in through the meeting service. The room's ? says to keep the tab
  open; closing it asks first, then tells everyone the room closed.
- **Dropped connections:** a player's seat is kept for 2 minutes. Their app
  reconnects by itself and catches up with the hand (a snapshot from the
  server); after the app was closed (or a browser page reloaded), Home's
  Multiplayer offers Rejoin Room. Meanwhile the room moves for them (in
  Hold'em it checks or folds after 3 s; after a whole hand away, they sit
  out until they are back), and the game waits when fewer than 2 can play.
- **Sit out** (Hold'em): ☰ > Sit Out keeps a player's seat and chips but
  deals them out from the next hand (they watch; their seat says Sitting out); ☰ > I'm
  Back deals them in again. A hand announced but not dealt yet is announced
  again, so the change counts from the very next hand.
- **Removing a player:** the host taps the person (in the room, or their
  seat at the table) > Remove. They go at once, or at the end of the hand they play;
  everyone is told, and the room refuses their token and their device (a
  random key the app keeps) from then on.
- **Out of chips** (Hold'em): with Rebuys (the host's rule) a player who
  loses every chip rebuys or leaves, and bots rebuy by themselves; without,
  they watch (their seat says Out). When one player has every chip, the game
  is over: the table shows its seats again, and the host starts a new game
  or picks another on Home.
- **Chat:** everyone in the room chats, spectators too: in the room and
  from ☰ > Chat at the table, with 8 quick messages; others' new messages show briefly at the top
  of the table. The server cleans each message (256 characters at most),
  takes 4 per player every 8 s, and keeps the last 64 for whoever joins or
  comes back.
- **Pre-actions** (Hold'em): while others act, a player ticks Check/Fold,
  Check, Call or Call Any in their buttons' places, and it is sent the
  moment their turn comes, so hands move faster (also in Free Play and Simple training on the
  device, where the play is still scored; not in Advanced training).

[docs/online_server.md](docs/online_server.md) is the step-by-step guide to
hosting and inviting friends: the firewall prompt, joining from anywhere,
what the public helpers see, when a direct connection isn't possible,
hosting from a phone, browser friends, what to do when something goes wrong,
and running the server on your own computer.

To ship the web version with the Windows app, build it once with
`dart run tool/build_web.dart --host` (into `build/web_host`, with the
engine's files included); every Windows build then copies it next to the app
as `data/web`. Without it, hosting still works for players with the app.

`dart run tool/host_check.dart` checks hosting on this computer: it starts a
room the way Create Room does, joins it at every address, reports the router
setup, and closes it. With `--no-router` it leaves the router alone (no port
opened). Run with plain Dart, it can't make direct connections;
`flutter test integration_test/peer_live_test.dart -d windows
--dart-define=PEER_LIVE=1` checks those through the real public helpers. The
first time, Windows Firewall asks whether the app may use the network.

`dart run bin/server.dart` runs the same server on its own, on your own
computer; players then enter `ws://<its address>:47474/ws` as the Server in
Play Online.
