import 'extraction_client.dart';

/// What a card of a topic asks on its front.
enum FrontShape {
  /// The concept's name, as the model wrote the card ("개념 이름").
  name,

  /// The content, so the name is recalled from it ("내용을 앞에").
  content,
}

/// How much a card of a topic says beside its front.
enum BackShape {
  /// The answer alone ("핵심만").
  core,

  /// The answer, then each example the page prints on a line of its own
  /// ("예시까지").
  examples,
}

/// The cards of one topic, which the user keeps or leaves out on the choice
/// screen, and the shape every card of it takes.
final class ChoiceTopic {
  ChoiceTopic(this.name);

  /// The topic's name; null for the cards of a function that names none.
  final String? name;

  final cards = <CandidateCard>[];

  bool on = true;
  FrontShape front = FrontShape.name;
  BackShape back = BackShape.core;

  /// The topic's first card, which the screen shows in the chosen shape.
  CandidateCard get sample => shape(cards.first);

  /// [card] in this topic's shape. With the content first, the back is the
  /// concept's name, and the examples, when chosen, follow the content.
  CandidateCard shape(CandidateCard card) {
    final content = [
      card.back,
      if (back == BackShape.examples) ...card.examples,
    ].join('\n');
    return switch (front) {
      FrontShape.name => CandidateCard(
        front: card.front,
        answer: switch (back) {
          BackShape.core => card.answer,
          BackShape.examples => [card.answer, ...card.examples].join('\n'),
        },
        partOfSpeech: card.partOfSpeech,
        topic: card.topic,
      ),
      FrontShape.content => CandidateCard(
        front: content,
        answer: card.front,
        topic: card.topic,
      ),
    };
  }
}

/// What the user chooses before Review: which topics of the one call's cards
/// to memorise, and in what shape.
final class Choice {
  Choice(List<CandidateCard> cards) {
    for (final card in cards) {
      var topic = topics.where((topic) => topic.name == card.topic).firstOrNull;
      if (topic == null) {
        topic = ChoiceTopic(card.topic);
        topics.add(topic);
      }
      topic.cards.add(card);
    }
  }

  /// The topics, in the order each first appears.
  final topics = <ChoiceTopic>[];

  int get cardCount =>
      topics.fold(0, (count, topic) => count + topic.cards.length);

  bool get anyOn => topics.any((topic) => topic.on);

  /// The cards of every topic that is on, each in its topic's shape, topic
  /// by topic.
  List<CandidateCard> get chosen => [
    for (final topic in topics)
      if (topic.on) ...topic.cards.map(topic.shape),
  ];
}
