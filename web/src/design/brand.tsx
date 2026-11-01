import Image from "next/image";

/** The brand's lockup in its light-ground and dark-ground files under public/brand/. */
type Mark = "lockup" | "stacked";

const sizes: Record<Mark, { width: number; height: number }> = {
  lockup: { width: 981, height: 200 },
  stacked: { width: 600, height: 484 },
};

/**
 * The brand's [mark], its words cocoa on a light theme and cream on a dark one, sized by [className].
 * With [alt] it is read as that name; without, it is decorative.
 */
export function BrandMark({
  mark,
  className,
  alt = "",
}: {
  mark: Mark;
  className: string;
  alt?: string;
}) {
  const { width, height } = sizes[mark];
  return (
    <>
      <Image
        src={`/brand/knowno-${mark}-light.svg`}
        alt={alt}
        width={width}
        height={height}
        unoptimized
        className={`${className} dark:hidden`}
      />
      <Image
        src={`/brand/knowno-${mark}-dark.svg`}
        alt={alt}
        width={width}
        height={height}
        unoptimized
        className={`${className} hidden dark:block`}
      />
    </>
  );
}

/** The moods of the mascot, each the same drawing (ADR 0140). */
export type MascotExpression = "thinking" | "happy" | "sad" | "sleepy";

/** The mascot in its [expression], on no ground of its own, sized by [className], decorative. */
export function Mascot({
  expression,
  className,
}: {
  expression: MascotExpression;
  className: string;
}) {
  return (
    <Image
      src={`/brand/knowno-${expression}.svg`}
      alt=""
      width={128}
      height={128}
      unoptimized
      className={className}
    />
  );
}
