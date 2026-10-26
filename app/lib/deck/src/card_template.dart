import 'model.dart';

/// The template every card is written in: 자유, each side a list of blocks
/// of any type (ADR 0114). A template only decides how the editor opens a
/// card; study draws by the blocks (ADR 0106).
const freeTemplate = 'free';

/// The version of the template this build writes.
const cardTemplateVersion = 1;

/// The templates earlier builds wrote beside [freeTemplate], at version 1:
/// 앞뒤, 빈칸 and 표. Each opens in the block editor as a 자유 card does.
const _earlierTemplates = {'flip', 'cloze', 'table'};

/// Whether this build's editor can edit [card]: one of no template, or of a
/// template some build of this app wrote at a version it knows. A template
/// or version a later build wrote opens read-only, and is never rewritten
/// (ADR 0106).
bool canEdit(Card card) => switch ((card.template, card.templateVersion)) {
  (null, _) => true,
  (_, final version?) when version > cardTemplateVersion => false,
  (final template?, _) =>
    template == freeTemplate || _earlierTemplates.contains(template),
};
