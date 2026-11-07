import '../../app/sounds.dart';
import '../table_controller.dart' show PlaybackSpeed;

export '../../app/sounds.dart' show SoundEffect;

/// The games' sound effects, at the app's volume. Silent when the speed is
/// Instant (as at the poker table: nothing to follow, nothing to hear).
///
/// Which game uses which: Gomoku stone, yourTurn, win, lose; Big Two and
/// Fight the Landlord deal, cardsDown, pass, bomb, yourTurn, win, lose;
/// Blackjack deal, chips (deal), check (stand), fold (surrender), win, lose.
abstract final class GameSounds {
  /// Where sounds go: the app's player; tests put a list's add here.
  static void Function(SoundEffect effect) output = Sounds.instance.play;

  static void play(SoundEffect effect, {required PlaybackSpeed speed}) {
    if (speed == PlaybackSpeed.instant) return;
    output(effect);
  }
}
