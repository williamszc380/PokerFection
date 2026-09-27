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
the site still works, but solving freezes the page. Every push to `main`
publishes the site (`.github/workflows/website.yml`).
