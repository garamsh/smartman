import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartman/account/account.dart';
import 'package:smartman/deck/deck.dart';
import 'package:smartman/shared/database.dart';
import 'package:smartman/study/study.dart';
import 'package:smartman/sync/sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'device.dart';

/// The local Supabase stack `supabase/test-sync.sh` starts, named by the
/// environment it runs this file in.
const _urlVariable = 'SMARTMAN_SYNC_TEST_URL';
const _keyVariable = 'SMARTMAN_SYNC_TEST_KEY';

List<Content> _text(String text) => [TextContent(text)];

void main() {
  final url = Platform.environment[_urlVariable];
  final key = Platform.environment[_keyVariable];
  final skip = url == null || key == null
      ? 'needs the local Supabase stack that supabase/test-sync.sh starts, '
            'which sets $_urlVariable and $_keyVariable'
      : null;

  late Scheduler scheduler;
  late UserId account;
  late Device a;
  late Device b;
  late String email;
  final clients = <SupabaseClient>[];

  setUpAll(() async {
    if (skip != null) return;
    scheduler = await Scheduler.load();
  });

  /// Two devices signed in to one new account, each with its own client.
  setUp(() async {
    if (skip != null) return;
    email = 'sync-${DateTime.now().microsecondsSinceEpoch}@example.com';
    const password = 'two-devices-password';
    // Password sign-in needs no PKCE flow, and so no storage for its verifier.
    const options = AuthClientOptions(authFlowType: AuthFlowType.implicit);
    final first = SupabaseClient(url!, key!, authOptions: options);
    final second = SupabaseClient(url, key, authOptions: options);
    clients.addAll([first, second]);
    final signUp = await first.auth.signUp(email: email, password: password);
    await second.auth.signInWithPassword(email: email, password: password);
    account = UserId(signUp.user!.id);
    expect(second.auth.currentUser?.id, account.value);
    a = Device('a', SupabaseSyncServer(first), scheduler);
    b = Device('b', SupabaseSyncServer(second), scheduler);
  });

  tearDown(() async {
    if (skip != null) return;
    await a.close();
    await b.close();
    for (final client in clients) {
      await client.dispose();
    }
    clients.clear();
  });

  Future<Deck> shared() async {
    final deck = await a.deck.createDeck('French');
    await a.sync(account);
    await b.sync(account);
    return deck;
  }

  Future<Card> addCard(Device device, Deck deck, String front) async {
    final saved = await device.deck.addCard(
      deck.id,
      front: _text(front),
      back: _text('$front back'),
      allowDuplicate: true,
    );
    return (saved as CardSaved).card;
  }

  test('a deck and card created on A appear on B', () async {
    final deck = await a.deck.createDeck('French');
    await addCard(a, deck, 'chat');
    expect(await b.deckNames(), isEmpty);

    await a.sync(account);
    await b.sync(account);

    expect(await b.deckNames(), ['French']);
    final cards = await b.deck.listCards(deck.id);
    expect(cards.map((card) => plainText(card.front)), ['chat']);
  }, skip: skip);

  test('an edit conflict keeps the later edit on both devices', () async {
    final deck = await shared();
    a.now = a.now.add(const Duration(minutes: 2));
    b.now = b.now.add(const Duration(minutes: 1));
    await a.deck.renameDeck(deck.id, 'Later');
    await b.deck.renameDeck(deck.id, 'Earlier');

    // A pushes first; B's earlier edit then reaches the server and loses.
    await a.sync(account);
    await b.sync(account);
    await a.sync(account);

    expect(await a.deckNames(), ['Later']);
    expect(await b.deckNames(), ['Later']);
  }, skip: skip);

  test('a delete beats a later concurrent edit on both devices', () async {
    final deck = await shared();
    a.now = a.now.add(const Duration(minutes: 1));
    b.now = b.now.add(const Duration(minutes: 2));
    await a.deck.deleteDeck(deck.id);
    await b.deck.renameDeck(deck.id, 'Edited after');

    await b.sync(account);
    await a.sync(account);
    await b.sync(account);

    expect(await a.deckNames(), isEmpty);
    expect(await b.deckNames(), isEmpty);
  }, skip: skip);

  test('reviews made offline on both converge, with each card state the '
      'engine fold of the union', () async {
    final deck = await shared();
    final card = await addCard(a, deck, 'chat');
    await a.sync(account);
    await b.sync(account);
    a.now = a.now.add(const Duration(days: 1));
    b.now = b.now.add(const Duration(days: 2));
    await a.answer(card.id, 'good', fuzz: 0.2);
    await b.answer(card.id, 'again', fuzz: 0.7);
    final before = (await a.stateOf(card.id))!;

    await a.sync(account);
    await b.sync(account);
    await a.sync(account);

    final union = (await a.foldOf(card.id))!;
    expect(before.stability, isNot(union.stability));
    for (final device in [a, b]) {
      final reviews = await device.db.select(device.db.reviews).get();
      expect(
        {for (final review in reviews) review.rating: review.fuzzFactor},
        {'good': 0.2, 'again': 0.7},
        reason: device.name,
      );
      final state = (await device.stateOf(card.id))!;
      expect(
        [state.stability, state.difficulty, state.due.millisecondsSinceEpoch],
        [union.stability, union.difficulty, union.due.millisecondsSinceEpoch],
        reason: device.name,
      );
    }
  }, skip: skip);

  test('an answer and its toggle written as the web app writes them '
      'converge with a phone\'s offline answer on both devices', () async {
    final deck = await shared();
    final card = await addCard(a, deck, 'chat');
    await a.sync(account);
    await b.sync(account);
    // The web app's session: the same account, signed in on its own client.
    final web = SupabaseClient(
      url!,
      key!,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    clients.add(web);
    await web.auth.signInWithPassword(
      email: email,
      password: 'two-devices-password',
    );
    String time(DateTime at) => at.toUtc().toIso8601String();
    final reviewId = const Uuid().v4();
    final answeredAt = a.now.add(const Duration(days: 1));
    final toggledAt = answeredAt.add(const Duration(minutes: 1));
    const webFactor = 0.3;
    ReviewRow review(String rating) => ReviewRow(
      id: reviewId,
      cardId: card.id.value,
      rating: rating,
      reviewedAt: answeredAt,
      durationMs: 3000,
      fuzzFactor: webFactor,
      updatedAt: answeredAt,
      dirty: false,
    );
    Future<void> writeState(String rating, DateTime editedAt) async {
      final state = (await scheduler.fold([review(rating)]))!;
      await web.from('card_states').upsert({
        'user_id': account.value,
        'card_id': card.id.value,
        'stability': state.stability,
        'difficulty': state.difficulty,
        'last_review': time(state.lastReview),
        'due': time(state.due),
        'updated_at': time(editedAt),
        'deleted_at': null,
      }, onConflict: 'user_id,card_id');
    }

    // The rows web/src/features/study/record-answer.ts writes: an answer
    // inserts its review and upserts the card's state; a toggle moves the
    // rating where the server's edit is older, and upserts the state again.
    await web.from('reviews').upsert({
      'id': reviewId,
      'user_id': account.value,
      'card_id': card.id.value,
      'rating': 'good',
      'reviewed_at': time(answeredAt),
      'duration_ms': 3000,
      'fuzz_factor': webFactor,
      'updated_at': time(answeredAt),
    }, ignoreDuplicates: true);
    await writeState('good', answeredAt);
    await web
        .from('reviews')
        .update({'rating': 'again', 'updated_at': time(toggledAt)})
        .eq('id', reviewId)
        .lt('updated_at', time(toggledAt));
    await writeState('again', toggledAt);
    // Meanwhile B answers the card offline, a day after the web.
    b.now = answeredAt.add(const Duration(days: 1));
    await b.answer(card.id, 'good', fuzz: 0.7);
    final offline = (await b.stateOf(card.id))!;

    await a.sync(account);
    await b.sync(account);
    await a.sync(account);

    final union = (await a.foldOf(card.id))!;
    // Control: B's state before the sync left out the web's answer.
    expect(offline.stability, isNot(union.stability));
    for (final device in [a, b]) {
      final reviews = await device.db.select(device.db.reviews).get();
      expect(
        {for (final review in reviews) review.rating: review.fuzzFactor},
        {'again': webFactor, 'good': 0.7},
        reason: device.name,
      );
      final state = (await device.stateOf(card.id))!;
      expect(
        [state.stability, state.difficulty, state.due.millisecondsSinceEpoch],
        [union.stability, union.difficulty, union.due.millisecondsSinceEpoch],
        reason: device.name,
      );
    }
  }, skip: skip);

  test('equal-key cards from both devices both survive', () async {
    final deck = await shared();
    await addCard(a, deck, 'chat');
    await addCard(b, deck, 'Chat');

    await a.sync(account);
    await b.sync(account);
    await a.sync(account);

    for (final device in [a, b]) {
      final cards = await device.deck.listCards(deck.id);
      expect(cards, hasLength(2), reason: device.name);
      expect(cards.map((card) => card.cardKey.value).toSet(), {'chat'});
    }
  }, skip: skip);
}
