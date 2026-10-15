import { type AnswerWrite, writeFailureMessages, type WriteResult } from "./answer-write";
import { schedule } from "./engine";
import { recordAnswer } from "./record-answer";

/**
 * Writes one answer or toggle: the engine, in the browser, replays the card's answers of this
 * session from its stored state, and the server stores the changed review and the state.
 */
export async function saveAnswer(write: AnswerWrite): Promise<WriteResult> {
  const scheduled = await schedule(write.before, write.history);
  if ("error" in scheduled) {
    console.error("the engine refused an answer", scheduled.error);
    return { saved: false, message: writeFailureMessages.scheduling };
  }
  const review = write.history.find((answer) => answer.id === write.change.reviewId);
  if (!review) throw new Error(`the write's history holds no review ${write.change.reviewId}`);
  return recordAnswer({
    cardId: write.cardId,
    review,
    change: write.change.kind,
    state: scheduled.state,
    editedAt: write.editedAt,
  });
}
