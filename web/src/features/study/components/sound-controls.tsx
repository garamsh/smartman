"use client";

import { Volume2 } from "lucide-react";
import { useEffect, useRef, useState } from "react";

import type { Sound } from "../session";

/**
 * A card side's sounds, each a round control named "소리 듣기" with its length under it, which
 * plays it from its signed address, or says so in a live region when it has none or the browser
 * cannot play it (ADR 0112). A sound pauses when its card goes. The browser keeps each sound once played, so playing it again reads
 * nothing more. Nothing plays on its own: a browser refuses sound before the page's first gesture.
 */
export function SoundControls({
  sounds,
  play = playSound,
}: {
  sounds: Sound[];
  /** Plays [url] once, resolving whether it could; the browser's player unless a test passes one. */
  play?: (url: string, players: Map<string, HTMLAudioElement>) => Promise<boolean>;
}) {
  const players = useRef(new Map<string, HTMLAudioElement>());
  const [failed, setFailed] = useState(false);
  // A sound goes with the card that showed it.
  useEffect(() => {
    const kept = players.current;
    return () => {
      for (const player of kept.values()) player.pause();
    };
  }, []);
  if (sounds.length === 0) return null;
  return (
    <div className="flex flex-col items-center gap-1">
      <div className="flex flex-wrap justify-center gap-3">
        {sounds.map((sound, index) => (
          <div key={`${sound.media}-${String(index)}`} className="flex flex-col items-center gap-1">
            <button
              type="button"
              aria-label="소리 듣기"
              onClick={() => {
                setFailed(false);
                const played = sound.url
                  ? play(sound.url, players.current)
                  : Promise.resolve(false);
                void played.then((ok) => {
                  setFailed(!ok);
                });
              }}
              className="pressable flex size-16 items-center justify-center rounded-full bg-brand-tint text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink"
            >
              <Volume2 aria-hidden className="size-8" strokeWidth={2} />
            </button>
            <span aria-hidden className="text-caption text-muted tabular-nums">
              {sound.length}
            </span>
          </div>
        ))}
      </div>
      <p aria-live="polite" className="text-caption text-dont-know-text">
        {failed ? "소리를 재생하지 못했어요" : ""}
      </p>
    </div>
  );
}

/** Plays [url] from the start through its kept player, made on its first play. */
async function playSound(url: string, players: Map<string, HTMLAudioElement>): Promise<boolean> {
  let player = players.get(url);
  if (!player) {
    player = new Audio(url);
    players.set(url, player);
  }
  player.currentTime = 0;
  try {
    await player.play();
    return true;
  } catch {
    // A refused or unreadable sound: the control says it could not play.
    return false;
  }
}
