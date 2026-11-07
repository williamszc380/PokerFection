/// The games other than Hold'em this app can show online: each game's own
/// online part (`lib/src/ui/games/<key>/online/<key>_online_ui.dart`,
/// owned by that game). Today all four are here. A game added later that
/// isn't listed is greyed out on Home while in a room ("Online soon"), and
/// a room playing a game this app doesn't list says "Update the app to
/// watch".
library;

import '../games/big_two/online/big_two_online_ui.dart';
import '../games/blackjack/online/blackjack_online_ui.dart';
import '../games/doudizhu/online/doudizhu_online_ui.dart';
import '../games/gomoku/online/gomoku_online_ui.dart';
import 'online_game_ui.dart';

final Map<String, OnlineGameUi> onlineGameUis = {
  for (final ui in <OnlineGameUi>[
    ?gomokuOnlineUi,
    ?blackjackOnlineUi,
    ?bigTwoOnlineUi,
    ?doudizhuOnlineUi,
  ])
    ui.key: ui,
};
