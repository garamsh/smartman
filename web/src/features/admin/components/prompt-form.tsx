"use client";

import { useActionState, useState } from "react";

import { maxNoteLength, maxPromptLength } from "../prompt-limits";
import { savePrompt, type SavePromptState } from "../save-prompt";

/**
 * The form that saves a new version, starting from [initialText]. Saving serves it to no one; the
 * version's page then tests or activates it.
 */
export function PromptForm({ initialText, basis }: { initialText: string; basis: string }) {
  const [state, action, pending] = useActionState<SavePromptState, FormData>(savePrompt, {
    message: null,
  });
  const [length, setLength] = useState(initialText.length);
  return (
    <form action={action} aria-label="새 버전" className="flex flex-col gap-3">
      <h2 className="text-section">새 버전</h2>
      <p className="text-secondary text-muted">
        {basis}에서 시작해요. 저장해도 바로 쓰이지 않아요: 버전 화면에서 테스트하거나 적용해요.
        카드의 형식과 검사는 서버 코드에 있어서 여기서 바뀌지 않아요.
      </p>
      <label className="flex flex-col gap-1">
        <span className="text-label font-semibold">프롬프트</span>
        <textarea
          name="text"
          defaultValue={initialText}
          required
          maxLength={maxPromptLength}
          rows={16}
          onChange={(event) => {
            setLength(event.target.value.length);
          }}
          className="rounded-field border border-outline bg-surface p-3 font-mono text-caption focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink"
        />
      </label>
      <p className="-mt-2 text-caption text-muted">
        {length.toLocaleString("ko-KR")} / {maxPromptLength.toLocaleString("ko-KR")}자
      </p>
      <label className="flex flex-col gap-1">
        <span className="text-label font-semibold">메모</span>
        <input
          name="note"
          maxLength={maxNoteLength}
          className="h-search w-full rounded-field border border-outline bg-surface px-4 text-body focus-visible:outline-2 focus-visible:-outline-offset-1 focus-visible:outline-ink"
        />
      </label>
      <button
        type="submit"
        disabled={pending}
        className="flex min-h-button items-center justify-center self-start rounded-button bg-ink px-5 text-label font-semibold text-surface focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink disabled:opacity-50"
      >
        새 버전으로 저장
      </button>
      <p role="status" className="text-caption text-muted empty:hidden">
        {state.message}
      </p>
    </form>
  );
}
