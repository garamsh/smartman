import { http, HttpResponse } from "msw";

import { supabaseUrl, testAccessToken, testUser } from "./handlers";

type Row = Record<string, unknown>;
type Table = "decks" | "cards" | "reviews" | "card_states";

const tables: readonly Table[] = ["decks", "cards", "reviews", "card_states"];

/** The columns each table's primary key holds, as server.md lists them. */
const keys: Record<Table, readonly string[]> = {
  decks: ["id"],
  cards: ["id"],
  reviews: ["id"],
  card_states: ["user_id", "card_id"],
};

/** The columns a client may update in each table: every one but a review's, as server.md grants. */
const updatable: Record<Table, readonly string[] | null> = {
  decks: null,
  cards: null,
  reviews: ["rating", "updated_at"],
  card_states: null,
};

function isTable(name: string | readonly string[] | undefined): name is Table {
  return typeof name === "string" && (tables as readonly string[]).includes(name);
}

/** Whether [row] passes one PostgREST filter, `<column>=<operator>.<value>`. */
function passes(row: Row, column: string, filter: string): boolean {
  const [operator, ...rest] = filter.split(".");
  const operand = rest.join(".");
  const value = row[column];
  switch (operator) {
    case "is":
      return operand === "null" ? value === null || value === undefined : false;
    case "eq":
      return String(value) === operand;
    case "in": {
      const list = operand.replace(/^\(|\)$/g, "").split(",");
      return list.map((item) => item.replace(/^"|"$/g, "")).includes(String(value));
    }
    case "lt":
      return typeof value === "string" && Date.parse(value) < Date.parse(operand);
    default:
      throw new Error(`the fake PostgREST does not know the filter ${column}=${filter}`);
  }
}

const reserved = new Set(["select", "order", "offset", "limit", "on_conflict", "columns"]);

function matching(rows: Row[], params: URLSearchParams): Row[] {
  return rows.filter((row) =>
    [...params].every(([column, filter]) => reserved.has(column) || passes(row, column, filter)),
  );
}

/** A request that waits until the test releases it. */
type Held = { release: () => void; released: Promise<void> };

/**
 * PostgREST over the four sync tables, in memory, for [testUser]'s session: what a test
 * seeds is what the app reads, and what the app writes lands in [rows]. A row a test seeds
 * for another user stands in for one row-level security lets every user read, as another
 * user's public deck and its cards; the request's filters decide whether it is returned. It applies the
 * filters the app sends, the paging of `offset` and `limit`, the server's revision on every
 * write, an upsert's `resolution`, and the reviews' column grant.
 */
export class FakePostgrest {
  readonly rows: Record<Table, Row[]> = { decks: [], cards: [], reviews: [], card_states: [] };
  /** Every request answered, as `<method> <table>`. */
  readonly requests: string[] = [];
  private revision = 0;
  private held: Partial<Record<Table, Held>> = {};
  private failing: Partial<Record<Table, number>> = {};

  /** Stores [rows] in [table] as the phone's sync would have, owned by [testUser] unless a row names its `user_id`. */
  seed(table: Table, ...rows: Row[]) {
    for (const row of rows) this.rows[table].push(this.stamp({ user_id: testUser.id, ...row }));
  }

  /** Holds every request to [table] unanswered until the returned function is called. */
  hold(table: Table): () => void {
    let release = () => undefined as void;
    const released = new Promise<void>((resolve) => {
      release = resolve;
    });
    this.held[table] = { release, released };
    return () => {
      delete this.held[table];
      release();
    };
  }

  /** Fails every request to [table] with HTTP [status] until the returned function is called. */
  fail(table: Table, status: number): () => void {
    this.failing[table] = status;
    return () => {
      delete this.failing[table];
    };
  }

  private stamp(row: Row): Row {
    this.revision += 1;
    return { ...row, revision: this.revision };
  }

  private keyOf(table: Table, row: Row): string {
    return keys[table].map((column) => String(row[column])).join("/");
  }

  private async gate(table: Table): Promise<Response | null> {
    await this.held[table]?.released;
    const status = this.failing[table];
    if (status === undefined) return null;
    return HttpResponse.json({ code: "", message: "failing" }, { status });
  }

  readonly handlers = [
    http.get(`${supabaseUrl}/rest/v1/:table`, async ({ request, params }) => {
      const { table } = params;
      if (!isTable(table)) return HttpResponse.json({}, { status: 404 });
      const refused = await this.gate(table);
      if (refused) return refused;
      if (request.headers.get("authorization") !== `Bearer ${testAccessToken}`) {
        return HttpResponse.json({ code: "42501", message: "permission denied" }, { status: 401 });
      }
      this.requests.push(`GET ${table}`);
      const url = new URL(request.url);
      const offset = Number(url.searchParams.get("offset") ?? 0);
      const limit = Number(url.searchParams.get("limit") ?? Infinity);
      const rows = matching(this.rows[table], url.searchParams);
      return HttpResponse.json(rows.slice(offset, offset + limit));
    }),
    http.post(`${supabaseUrl}/rest/v1/:table`, async ({ request, params }) => {
      const { table } = params;
      if (!isTable(table)) return HttpResponse.json({}, { status: 404 });
      const refused = await this.gate(table);
      if (refused) return refused;
      this.requests.push(`POST ${table}`);
      const body: unknown = await request.json();
      const incoming = (Array.isArray(body) ? body : [body]) as Row[];
      const ignore = request.headers.get("prefer")?.includes("resolution=ignore-duplicates");
      for (const row of incoming) {
        const at = this.rows[table].findIndex(
          (stored) => this.keyOf(table, stored) === this.keyOf(table, row),
        );
        if (at === -1) this.rows[table].push(this.stamp(row));
        else if (!ignore) this.rows[table][at] = this.stamp(row);
      }
      return new HttpResponse(null, { status: 201 });
    }),
    http.patch(`${supabaseUrl}/rest/v1/:table`, async ({ request, params }) => {
      const { table } = params;
      if (!isTable(table)) return HttpResponse.json({}, { status: 404 });
      const refused = await this.gate(table);
      if (refused) return refused;
      this.requests.push(`PATCH ${table}`);
      const body = (await request.json()) as Row;
      const allowed = updatable[table];
      if (allowed && Object.keys(body).some((column) => !allowed.includes(column))) {
        return HttpResponse.json({ code: "42501", message: "permission denied" }, { status: 403 });
      }
      const url = new URL(request.url);
      for (const row of matching(this.rows[table], url.searchParams)) {
        const at = this.rows[table].indexOf(row);
        this.rows[table][at] = this.stamp({ ...row, ...body });
      }
      return new HttpResponse(null, { status: 204 });
    }),
  ];
}
