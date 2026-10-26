import {
  BookOpen,
  Brain,
  Briefcase,
  Calculator,
  Code,
  FlaskConical,
  Globe,
  Landmark,
  Languages,
  Layers,
  type LucideProps,
  Music,
  Palette,
  Pencil,
  Star,
} from "lucide-react";
import type { ReactNode } from "react";

import { deckColor, deckFill } from "../deck-tint";
import type { Deck } from "../library";

/** Draws one icon with [props]. */
type DrawIcon = (props: LucideProps) => ReactNode;

/**
 * The icons a deck's tile can hold, by the key a deck stores: the app's `DeckIcon` keys, each
 * drawn with the Lucide icon the app draws for it (`deckIconData` in
 * app/lib/deck/src/deck_row.dart).
 */
const deckIcons: Record<string, DrawIcon> = {
  layers: (props) => <Layers {...props} />,
  book: (props) => <BookOpen {...props} />,
  languages: (props) => <Languages {...props} />,
  pencil: (props) => <Pencil {...props} />,
  flask: (props) => <FlaskConical {...props} />,
  calculator: (props) => <Calculator {...props} />,
  globe: (props) => <Globe {...props} />,
  music: (props) => <Music {...props} />,
  palette: (props) => <Palette {...props} />,
  brain: (props) => <Brain {...props} />,
  code: (props) => <Code {...props} />,
  landmark: (props) => <Landmark {...props} />,
  briefcase: (props) => <Briefcase {...props} />,
  star: (props) => <Star {...props} />,
};

/** Draws [deck]'s icon: the one it stores, or `layers` for none or a key this version does not know. */
function drawIcon(deck: Deck): DrawIcon {
  const stored = deck.icon;
  return (
    (stored !== undefined && Object.hasOwn(deckIcons, stored) && deckIcons[stored]) ||
    ((props) => <Layers {...props} />)
  );
}

/**
 * A deck's icon in ink on its colour from the deck palette, as the app draws its tile (ADR 0103);
 * hidden from screen readers. [size] sizes the tile; the icon takes half of it.
 */
export function DeckTile({ deck, size = "size-deck-tile" }: { deck: Deck; size?: string }) {
  return (
    <span
      aria-hidden
      className={`flex shrink-0 items-center justify-center rounded-field text-ink ${size} ${deckFill(deckColor(deck))}`}
    >
      {drawIcon(deck)({ className: "size-1/2", strokeWidth: 2 })}
    </span>
  );
}
