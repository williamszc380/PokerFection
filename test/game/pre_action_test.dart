import 'package:flutter_test/flutter_test.dart';
import 'package:pokerfection/src/engine/actions.dart';
import 'package:pokerfection/src/game/pre_action.dart';
import 'package:pokerfection/src/gto/spot_strategy.dart';

/// The user's choices at a turn facing [toCall] (0: checking is free), and
/// what they may do.
(List<SpotAction>, LegalActions) _turn(int toCall) => (
      [
        SpotAction(
          kind: SpotActionKind.fold,
          amount: 0,
          action: const PlayerAction.fold(),
          unavailable: toCall > 0 ? null : Unavailable.checkIsFree,
        ),
        toCall == 0
            ? const SpotAction(kind: SpotActionKind.check, amount: 0, action: PlayerAction.check())
            : SpotAction(kind: SpotActionKind.call, amount: toCall, action: const PlayerAction.call()),
        const SpotAction(kind: SpotActionKind.allIn, amount: 10000, action: PlayerAction.raiseTo(10000)),
      ],
      LegalActions(
        toCall: toCall,
        canRaise: true,
        minRaiseTo: 2 * toCall + 200,
        maxRaiseTo: 10000,
        currentBet: toCall,
        streetBet: 0,
        stack: 10000,
        pot: 300 + toCall,
      ),
    );

void main() {
  test('a pre-action plays at the turn only while it still fits', () {
    final (freeMenu, free) = _turn(0);
    final (betMenu, bet) = _turn(200);
    final (raiseMenu, raised) = _turn(600);
    // Check/Fold: checks when it is free, else folds.
    expect(PreAction.checkFold.choiceIn(freeMenu, free, picked: 0), 1);
    expect(PreAction.checkFold.choiceIn(betMenu, bet, picked: 0), 0);
    // Check: cancelled once someone bets.
    expect(PreAction.check.choiceIn(freeMenu, free, picked: 0), 1);
    expect(PreAction.check.fits(picked: 0, toCall: 200), isFalse);
    expect(PreAction.check.choiceIn(betMenu, bet, picked: 0), isNull);
    // Call: only the amount it was picked for.
    expect(PreAction.call.choiceIn(betMenu, bet, picked: 200), 1);
    expect(PreAction.call.fits(picked: 200, toCall: 600), isFalse);
    expect(PreAction.call.choiceIn(raiseMenu, raised, picked: 200), isNull);
    // Call Any: whatever it costs, or a check when it is free.
    expect(PreAction.callAny.choiceIn(raiseMenu, raised, picked: 200), 1);
    expect(PreAction.callAny.choiceIn(freeMenu, free, picked: 200), 1);
  });
}
