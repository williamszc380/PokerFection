# PokerFection

Practice No-Limit Hold'em decisions against bots. In GTO Training, every
decision is scored against a game-theory-optimal answer, solved on your own
device; the Preflop Charts show GTO ranges for 2 to 8 players.

**Play in your browser:** https://williamszc380.github.io/PokerFection/

## Running and building

- Windows: `flutter run -d windows`
- Web: `dart run tool/build_web.dart` builds the site into `build/web`.

The web build is the app plus the solvers' Web Worker
(`lib/solver_worker.dart`), which `flutter build web` leaves out: without it
the site still works, but solving freezes the page. The worker is compiled
to WebAssembly, which solves 1.1 to 1.6 times faster, and to JavaScript for
browsers that can't run that (no WasmGC); `dart run tool/worker_bench.dart`
times both in Edge or Chrome. Every push to `main` publishes the site
(`.github/workflows/website.yml`).

## Drills

Every Mistake or Blunder in solo GTO Training (Simple or Advanced) is saved
as a spot: the whole hand up to that decision (table, stacks, every player's
cards, the board and the betting). **Drills** on the main menu shows how many
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

Online play (main menu: **Play > Multiplayer**) needs no outside service:
**Create Room** runs the game server inside the app of whoever creates the
room (Windows, Android or iOS), on port 47474 (or one of the next few when it
is taken), and the host's app joins it like everyone else. The room ends when
the host leaves.

- **Same Wi-Fi:** friends join with the room code alone (the app finds the
  room on the network), or with the invite.
- **Internet:** the app asks the router to open the port (UPnP). The lobby
  shows "Internet: ready" when that worked; its "?" explains opening the port
  by hand. Some providers (shared addresses, CGNAT) and mobile data make it
  impossible. iPhones and iPads skip the automatic setup.
- **Invite:** a link that opens the app with every address of the host to
  try (local first); a host that serves the web version also has a browser
  link to copy.
- **Browser players** open `http://<host address>:47474/?code=ABCDE`: the
  host's app serves the web version there. The website can't reach a home
  server (browsers block it from https pages), and a browser can't host.
- **Dropped connections:** a player's seat is kept for 2 minutes. Their app
  reconnects by itself and catches up with the hand (a snapshot from the
  server); after the app was closed (or a browser page reloaded), Play >
  Multiplayer offers Rejoin Room. Meanwhile the server checks or folds for
  them after 3 s (after a whole hand away, they sit out until they are
  back), and the game waits when fewer than 2 can play.
- **Sit out:** ☰ > Sit Out keeps a player's seat and chips but deals them
  out from the next hand (they watch; their seat says Sitting out); ☰ > I'm
  Back deals them in again. A hand announced but not dealt yet is announced
  again, so the change counts from the very next hand.
- **Removing a player:** the host taps a player's seat (lobby, or ☰ > Edit
  Table) > Remove. They go at once, or at the end of the hand they play;
  everyone is told, and the room refuses their token and their device (a
  random key the app keeps) from then on.
- **Out of chips:** with Rebuys (the host's rule) a player who loses every
  chip rebuys or leaves, and bots rebuy by themselves; without, they watch
  (their seat says Out). When one player has every chip, the game is over:
  everyone is back in the lobby, and the host starts a new game.
- **Chat:** everyone in the room chats in the lobby and from ☰ > Chat at the
  table, with 8 quick messages; others' new messages show briefly at the top
  of the table. The server cleans each message (256 characters at most),
  takes 4 per player every 8 s, and keeps the last 64 for whoever joins or
  comes back.
- **Pre-actions:** while others act, a player ticks Check/Fold, Check, Call
  or Call Any in their buttons' places, and it is sent the moment their turn
  comes, so hands move faster (also in Free Play and Simple training on the
  device, where the play is still scored; not in Advanced training).

[docs/online_server.md](docs/online_server.md) is the step-by-step guide to
hosting and inviting friends: the firewall prompt, router setup (automatic
and by hand), CGNAT and mobile data, hosting from a phone, browser friends,
what to do when something goes wrong, and running the server on your own
computer.

To ship the web version with the Windows app, build it once with
`dart run tool/build_web.dart --host` (into `build/web_host`, with the
engine's files included); every Windows build then copies it next to the app
as `data/web`. Without it, hosting still works for players with the app.

`dart run tool/host_check.dart` checks hosting on this computer: it starts a
room the way Create Room does, joins it at every address, reports the router
setup, and closes it. With `--no-router` it leaves the router alone (no port
opened). The first time, Windows Firewall asks whether the app may use the
network.

`dart run bin/server.dart` runs the same server on its own, on your own
computer; players then enter `ws://<its address>:47474/ws` as the Server in
Play Online.
