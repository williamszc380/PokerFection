/// The games other than Hold'em that rooms can play: each game's own
/// online support (`lib/src/games/<key>/online/<key>_runner.dart`, owned by
/// that game), null until the game adds it. A room offers the games listed
/// here (RoomState.games); in a room, Home greys out the others.
library;

import '../../games/big_two/online/big_two_runner.dart';
import '../../games/blackjack/online/blackjack_runner.dart';
import '../../games/doudizhu/online/doudizhu_runner.dart';
import '../../games/gomoku/online/gomoku_runner.dart';
import 'game_runner.dart';

final Map<String, OnlineGame> onlineGames = {
  for (final g in [?gomokuOnline, ?bigTwoOnline, ?doudizhuOnline, ?blackjackOnline]) g.key: g,
};
