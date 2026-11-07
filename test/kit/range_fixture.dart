/// A stand-in for a card game's range job, to test the kit's range sheet:
/// it deals random hidden hands (a seeded generator, so the same input
/// always gives the same range) from one deck, with or without the two
/// jokers (Fight the Landlord's ranks, or Big Two's), and tallies them with
/// OpponentRange.tally. Plus the names the sheet shows in three languages.
library;

import 'package:pokerfection/src/app/app_settings.dart';
import 'package:pokerfection/src/kit/jobs/jobs_core.dart';
import 'package:pokerfection/src/kit/range.dart';
import 'package:pokerfection/src/ui/kit/range_sheet.dart';

typedef Json = Map<String, Object?>;

const bigTwoRanks = ['3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A', '2'];
const landlordRanks = [...bigTwoRanks, 'SJ', 'BJ'];

const bigTwoKinds = ['pair', 'triple', 'straight', 'flush', 'fullHouse', 'quads', 'straightFlush', 'twos:1', 'twos:2'];
const landlordKinds = ['pair', 'trio', 'straight', 'pairs', 'airplane', 'bomb', 'rocket'];

/// Input: {seat, cards, jokers, samples, seed}.
class FakeRangeJob extends GameJob<Json, OpponentRange> {
  const FakeRangeJob();

  @override
  String get name => 'kit.fakeRange';

  @override
  Object? encodeInput(Json input) => input;
  @override
  Json decodeInput(Object? json) => json! as Json;
  @override
  Object? encodeOutput(OpponentRange output) => output.toJson();
  @override
  OpponentRange decodeOutput(Object? json) => OpponentRange.fromJson(json);

  @override
  OpponentRange run(Json input, JobContext context) {
    final jokers = input['jokers'] == true;
    final ranks = jokers ? landlordRanks : bigTwoRanks;
    final deck = [
      for (final r in bigTwoRanks) ...[r, r, r, r],
      if (jokers) ...['SJ', 'BJ'],
    ];
    var state = (input['seed'] as int? ?? 1) * 2654435761 % 4294967296;
    int next(int n) {
      state = (state * 1103515245 + 12345) % 2147483648;
      return state % n;
    }

    final cards = input['cards']! as int;
    final hands = <List<String>>[
      for (var s = 0; s < (input['samples'] as int? ?? 200); s++)
        () {
          final pool = [...deck];
          return [for (var i = 0; i < cards; i++) pool.removeAt(next(pool.length))];
        }(),
    ];
    return OpponentRange.tally(
      seat: input['seat']! as int,
      hands: hands,
      rankOrder: [for (final r in ranks) (r, r.endsWith('J') && r.length == 2 ? 1 : 4)],
      kinds: jokers ? landlordKinds : bigTwoKinds,
      combosOf: (hand) => jokers ? _landlordCombos(hand) : _bigTwoCombos(hand),
    );
  }
}

Map<String, int> _count(List<String> hand) {
  final count = <String, int>{};
  for (final r in hand) {
    count[r] = (count[r] ?? 0) + 1;
  }
  return count;
}

Set<String> _straights(Map<String, int> count, {int length = 5, int need = 1}) {
  const order = ['3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'];
  return {
    for (var i = 0; i + length <= order.length; i++)
      if (order.sublist(i, i + length).every((r) => (count[r] ?? 0) >= need))
        order.sublist(i, i + length).map((r) => need == 1 ? r : '$r$r').join('-'),
  };
}

Map<String, Set<String>> _bigTwoCombos(List<String> hand) {
  final count = _count(hand);
  final twos = count['2'] ?? 0;
  return {
    'pair': {for (final MapEntry(:key, :value) in count.entries) if (value >= 2) '$key-$key'},
    'triple': {for (final MapEntry(:key, :value) in count.entries) if (value >= 3) '$key-$key-$key'},
    'straight': _straights(count),
    'quads': {for (final MapEntry(:key, :value) in count.entries) if (value == 4) '$key×4'},
    'twos:1': {if (twos >= 1) '2'},
    'twos:2': {if (twos >= 2) '2-2'},
  };
}

Map<String, Set<String>> _landlordCombos(List<String> hand) {
  final count = _count(hand);
  return {
    'pair': {for (final MapEntry(:key, :value) in count.entries) if (value >= 2) '$key-$key'},
    'trio': {for (final MapEntry(:key, :value) in count.entries) if (value >= 3) '$key-$key-$key'},
    'straight': _straights(count),
    'pairs': _straights(count, length: 3, need: 2),
    'airplane': _straights(count, length: 2, need: 3),
    'bomb': {for (final MapEntry(:key, :value) in count.entries) if (value == 4) '$key×4'},
    'rocket': {if (count.containsKey('SJ') && count.containsKey('BJ')) 'SJ-BJ'},
  };
}

/// The sheet's names for the fake ranges, in [language].
RangeLook fakeLook(AppLanguage language) {
  String rank(String r) => switch (r) {
        'T' => '10',
        'SJ' => language == AppLanguage.chinese ? '小' : 'jk',
        'BJ' => language == AppLanguage.chinese ? '大' : 'JK',
        _ => r,
      };
  const names = {
    AppLanguage.english: {
      'pair': 'Pairs', 'triple': 'Triples', 'straight': 'Straights', 'flush': 'Flushes',
      'fullHouse': 'Full houses', 'quads': 'Four of a kind', 'straightFlush': 'Straight flushes',
      'twos:1': 'A 2', 'twos:2': 'Two 2s', 'trio': 'Trios', 'pairs': 'Pair chains',
      'airplane': 'Airplanes', 'bomb': 'Bombs', 'rocket': 'Rocket',
    },
    AppLanguage.spanish: {
      'pair': 'Parejas', 'triple': 'Tríos', 'straight': 'Escaleras', 'flush': 'Colores',
      'fullHouse': 'Full', 'quads': 'Póker', 'straightFlush': 'Escaleras de color',
      'twos:1': 'Un 2', 'twos:2': 'Dos 2', 'trio': 'Tríos', 'pairs': 'Parejas seguidas',
      'airplane': 'Aviones', 'bomb': 'Bombas', 'rocket': 'Cohete',
    },
    AppLanguage.chinese: {
      'pair': '对子', 'triple': '三条', 'straight': '顺子', 'flush': '同花',
      'fullHouse': '葫芦', 'quads': '四条', 'straightFlush': '同花顺',
      'twos:1': '一张2', 'twos:2': '两张2', 'trio': '三张', 'pairs': '连对',
      'airplane': '飞机', 'bomb': '炸弹', 'rocket': '王炸',
    },
  };
  return RangeLook(
    rankLabel: rank,
    comboLabel: (kind) => names[language]![kind] ?? kind,
    comboText: (combo) => combo.split('-').map((r) => r.replaceAll('T', '10')).map((r) => rank(r)).join(' '),
  );
}
