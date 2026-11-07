import 'package:flutter/widgets.dart';

import '../../../../app/app_settings.dart';

/// The few words the room's game of Fight the Landlord adds to the solo
/// game's (LandlordStrings): who won a deal when it isn't the player.
abstract class LandlordOnlineStrings {
  const LandlordOnlineStrings();

  static LandlordOnlineStrings forLanguage(AppLanguage language) => switch (language) {
    AppLanguage.english => const _En(),
    AppLanguage.spanish => const _Es(),
    AppLanguage.chinese => const _Zh(),
  };

  static LandlordOnlineStrings of(BuildContext context) => forLanguage(AppSettings.of(context).language);

  /// The landlord [name] went out first.
  String landlordWins(String name);

  /// A peasant went out first: both peasants win.
  String get peasantsWin;
}

class _En extends LandlordOnlineStrings {
  const _En();
  @override
  String landlordWins(String name) => 'Landlord $name wins';
  @override
  String get peasantsWin => 'Peasants win';
}

class _Es extends LandlordOnlineStrings {
  const _Es();
  @override
  String landlordWins(String name) => 'Gana el terrateniente $name';
  @override
  String get peasantsWin => 'Ganan los campesinos';
}

class _Zh extends LandlordOnlineStrings {
  const _Zh();
  @override
  String landlordWins(String name) => '地主$name赢了';
  @override
  String get peasantsWin => '农民赢了';
}
