import Image from "next/image";

/** The brand's mark in its light-ground and dark-ground files under public/brand/. */
type Mark = "lockup" | "symbol";

const sizes: Record<Mark, { width: number; height: number }> = {
  lockup: { width: 667, height: 200 },
  symbol: { width: 200, height: 200 },
};

/**
 * The brand's [mark], navy on a light theme and white on a dark one, sized by [className].
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
        src={`/brand/smartman-${mark}-light.svg`}
        alt={alt}
        width={width}
        height={height}
        unoptimized
        className={`${className} dark:hidden`}
      />
      <Image
        src={`/brand/smartman-${mark}-dark.svg`}
        alt={alt}
        width={width}
        height={height}
        unoptimized
        className={`${className} hidden dark:block`}
      />
    </>
  );
}

/** The mascot in a round [className] fill, decorative. */
export function Mascot({ className }: { className: string }) {
  return (
    <span aria-hidden className={`flex items-center justify-center rounded-full ${className}`}>
      <BrandMark mark="symbol" className="size-2/3" />
    </span>
  );
}
