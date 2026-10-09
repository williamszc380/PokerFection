import 'dart:math';

import '../game/table_session.dart';
import '../gto/spot_strategy.dart';
import '../l10n/strings.dart';

/// "Fold", "Call 1.50 BB", "Raise to 8.00 BB", "All-in 100.00 BB" (in the app's language).
String spotActionLabel(S s, SpotAction a) {
  final amount = formatBb(a.amount, unit: true);
  return switch (a.kind) {
    SpotActionKind.fold => s.fold,
    SpotActionKind.check => s.check,
    SpotActionKind.call => s.call(amount),
    SpotActionKind.raise => s.raiseTo(amount, null),
    SpotActionKind.allIn => s.allIn(amount),
  };
}

/// Formats chips as big blinds, always with two decimals: 250 -> "2.50".
String formatBb(int chips, {bool unit = false}) {
  final text = (chips / TableConfig.bigBlind).toStringAsFixed(2);
  return unit ? '$text BB' : text;
}

/// A wait, short and rounded: "10 min", "1 h", "3 days", "2 weeks",
/// "4 months", "2 years" (a minute at least).
String formatWait(S s, Duration wait) {
  final minutes = max(1, (wait.inSeconds / 60).round());
  if (minutes < 60) return s.waitTime(minutes, WaitUnit.minutes);
  final hours = (minutes / 60).round();
  if (hours < 24) return s.waitTime(hours, WaitUnit.hours);
  final days = (hours / 24).round();
  if (days < 7) return s.waitTime(days, WaitUnit.days);
  if (days < 56) return s.waitTime((days / 7).round(), WaitUnit.weeks);
  if (days < 365) return s.waitTime((days / 30.44).round(), WaitUnit.months);
  return s.waitTime((days / 365.25).round(), WaitUnit.years);
}

/// Like [formatBb] but always with a sign: "+2.50 BB", "-1.00 BB", "0.00 BB".
String formatSignedBb(int chips) {
  final sign = chips > 0 ? '+' : (chips < 0 ? '-' : '');
  return '$sign${formatBb(chips.abs(), unit: true)}';
}
