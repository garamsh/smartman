/**
 * The height of each of the study screen's two card places, and of their placeholders: a third
 * of the screen, from 208 to 300 px, so 모른다 and 안다 stay on screen under the current card
 * whatever it holds (ADR 0123). A module without `'use client'`, so the server-rendered skeleton
 * reads the same value.
 */
export const cardHeight = "h-[32dvh] max-h-75 min-h-52";
