import { render as renderTree } from "@testing-library/react";
import type { ReactNode } from "react";

/**
 * Renders [component] with Testing Library, first awaiting it when it is an async Server
 * Component, which Testing Library cannot render itself.
 */
export async function render<P extends object>(
  component: (props: P) => ReactNode | Promise<ReactNode>,
  props: P,
) {
  return renderTree(<>{await component(props)}</>);
}
