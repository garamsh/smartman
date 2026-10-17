import { ReadFailure } from "@/features/decks";
import { readRecord, RecordView } from "@/features/study";

/** The 기록 page's content, read on the server and folded through the engine there (ADR 0047). */
export async function RecordContent() {
  const read = await readRecord();
  if ("failure" in read) return <ReadFailure failure={read.failure} />;
  return <RecordView {...read.record} />;
}
