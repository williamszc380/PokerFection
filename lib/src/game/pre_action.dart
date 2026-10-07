import '../engine/actions.dart';
import '../gto/spot_strategy.dart';

/// A play the user picks while another player acts (a pre-action): it is
/// played the moment their turn comes, if it still fits. It lasts until the
/// end of the street.
enum PreAction {
  /// Check if it is free, else fold.
  checkFold,

  /// Check; cancelled once someone bets.
  check,

  /// Call the amount the user faced when picking it; cancelled once that
  /// changes.
  call,

  /// Call whatever it costs (check if it is free).
  callAny;

  /// Whether this pick, made when the user had [picked] to call, still
  /// stands now that they have [toCall] to call (on the same street).
  bool fits({required int picked, required int toCall}) => switch (this) {
        PreAction.check => toCall == 0,
        PreAction.call => toCall == picked,
        PreAction.checkFold || PreAction.callAny => true,
      };

  /// At the user's turn ([options]): the choice of [menu] this pick plays
  /// (fold, or check or call), or null if it no longer fits.
  int? choiceIn(List<SpotAction> menu, LegalActions options, {required int picked}) {
    if (!fits(picked: picked, toCall: options.toCall)) return null;
    final fold = this == PreAction.checkFold && !options.canCheck;
    final choice = menu.indexWhere(
      (a) => fold ? a.kind == SpotActionKind.fold : a.kind == SpotActionKind.check || a.kind == SpotActionKind.call,
    );
    return choice < 0 || !menu[choice].available ? null : choice;
  }
}
