import '../game/table_session.dart';
import '../gto/spot_strategy.dart';
import '../l10n/strings.dart';

/// "Fold", "Call 1.5 BB", "Raise to 7.5 BB (3×)", "Raise to 2.8 BB (0.5× pot)", "All-in 100 BB"
/// (in the app's language).
String spotActionLabel(S s, SpotAction a) {
  final amount = formatBb(a.amount, unit: true);
  final size = sizeText(s, a);
  return switch (a.kind) {
    SpotActionKind.fold => s.fold,
    SpotActionKind.check => s.check,
    SpotActionKind.call => s.call(amount),
    SpotActionKind.raise => s.raiseTo(amount, size),
    SpotActionKind.allIn => s.allIn(amount),
  };
}

/// A sized raise's size: "3×" before the flop, "0.5× pot" after it.
String? sizeText(S s, SpotAction a) {
  final multiple = a.multiple, share = a.potShare;
  if (multiple != null) return s.multiple(multiple);
  return share == null ? null : s.potShare(share);
}

/// Formats chips as big blinds, always with two decimals: 250 -> "2.50".
String formatBb(int chips, {bool unit = false}) {
  final text = (chips / TableConfig.bigBlind).toStringAsFixed(2);
  return unit ? '$text BB' : text;
}

/// Like [formatBb] but always with a sign: "+2.5 BB", "-1 BB", "0 BB".
String formatSignedBb(int chips) {
  final sign = chips > 0 ? '+' : (chips < 0 ? '-' : '');
  return '$sign${formatBb(chips.abs(), unit: true)}';
}
