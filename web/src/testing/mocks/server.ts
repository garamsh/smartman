import { setupServer } from "msw/node";

import { handlers, staticFiles } from "./handlers";

export const server = setupServer(...handlers, staticFiles);
