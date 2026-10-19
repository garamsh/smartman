import { http, HttpResponse } from "msw";

import { bearerUser, otherUser, supabaseUrl, testUser } from "./handlers";

type Row = Record<string, unknown>;

/** A deck as the admin functions see it, its cards' sides as plain text. */
export type FakeDeck = {
  id: string;
  name: string;
  ownerId: string;
  visibility: "public" | "private";
  hidden: boolean;
  deleted: boolean;
  description: string | null;
  copies: number;
  publishedAt: string | null;
  cards: { id: string; front: string; back: string }[];
  reports: { reason: string; at: string }[];
};

/** A user as the admin functions see it. */
export type FakeUser = {
  id: string;
  email: string;
  createdAt: string;
  lastAnswerAt: string | null;
  decks: number;
  cards: number;
  extractionsToday: number;
};

const text = (value: string) => [{ type: "text", payload: { text: value } }];

/**
 * The server's admin functions (ADR 0070), in memory: each answers for a signed-in admin and
 * refuses anyone else with `42501`, as `private.require_admin` does, and every write is recorded
 * in [audit] as the server records it. [testUser] is the one admin until a test says otherwise;
 * [otherUser] is not one.
 */
export class FakeAdmin {
  readonly admins = new Map<string, { grantedAt: string; grantedBy: string | null }>([
    [testUser.id, { grantedAt: "2026-10-19T00:00:00Z", grantedBy: null }],
  ]);
  readonly users: FakeUser[] = [
    {
      id: testUser.id,
      email: testUser.email,
      createdAt: "2026-10-01T00:00:00Z",
      lastAnswerAt: null,
      decks: 0,
      cards: 0,
      extractionsToday: 0,
    },
    {
      id: otherUser.id,
      email: otherUser.email,
      createdAt: "2026-10-15T00:00:00Z",
      lastAnswerAt: "2026-10-18T09:30:00Z",
      decks: 2,
      cards: 3,
      extractionsToday: 4,
    },
  ];
  readonly decks: FakeDeck[] = [];
  readonly audit: Row[] = [];
  overview: Row = {
    users: 2,
    new_users_7d: 1,
    new_users_30d: 2,
    studied_today: 1,
    studied_7d: 2,
    extractions_today: 5,
  };
  extractionsByDay: Row[] = [];
  /** The plans' settings, seeded as the migration seeds them. */
  readonly plans: { id: string; model: string; daily_limit: number; updated_by: string | null }[] =
    ["free", "pro", "special"].map((id) => ({
      id,
      model: "anthropic/claude-haiku-5.5",
      daily_limit: 30,
      updated_by: null,
    }));
  /** The saved prompt versions, oldest first; the seed, prompt v8, is version 1. */
  readonly prompts: { id: number; text: string; note: string; by: string | null }[] = [
    { id: 1, text: "Prompt v8.\nKeep each fact.", note: "prompt v8", by: null },
  ];
  /** The version each label names; no `test` while none is set. */
  readonly promptLabels = new Map<"active" | "test", number>([["active", 1]]);
  /** Each suspended user's suspension. */
  readonly suspensions = new Map<string, { reason: string; by: string }>();
  /** Each deck removed from sharing, and why. */
  readonly removals = new Map<string, string>();
  /** Each user's grant of a plan other than Free. */
  readonly userPlans = new Map<
    string,
    { plan: string; endsAt: string | null; grantedBy: string | null }
  >();
  /** The functions called, as `<name> <args as JSON>`. */
  readonly calls: string[] = [];

  /** Adds [deck] to the server. */
  seedDeck(deck: Partial<FakeDeck> & Pick<FakeDeck, "id" | "name">) {
    this.decks.push({
      ownerId: otherUser.id,
      visibility: "public",
      hidden: false,
      deleted: false,
      description: null,
      copies: 0,
      publishedAt: "2026-10-17T00:00:00Z",
      cards: [],
      reports: [],
      ...deck,
    });
  }

  private owner(deck: FakeDeck): Row {
    const user = this.users.find((candidate) => candidate.id === deck.ownerId);
    return { owner_id: deck.ownerId, owner_email: user?.email ?? "", owner_name: null };
  }

  private promptRow(prompt: FakeAdmin["prompts"][number]): Row {
    return {
      id: prompt.id,
      note: prompt.note,
      length: prompt.text.length,
      created_by_email: this.users.find((user) => user.id === prompt.by)?.email ?? null,
      created_at: "2026-10-19T04:00:00Z",
      labels: (["active", "test"] as const).filter(
        (label) => this.promptLabels.get(label) === prompt.id,
      ),
    };
  }

  private reasons(deck: FakeDeck): string[] {
    return [...new Set(deck.reports.map((report) => report.reason))].sort();
  }

  private record(admin: string, action: string, kind: string, target: string, detail: Row) {
    this.audit.unshift({
      id: this.audit.length + 1,
      created_at: "2026-10-19T03:00:00Z",
      admin_email: this.users.find((user) => user.id === admin)?.email ?? "",
      action,
      target_kind: kind,
      target_id: target,
      detail,
    });
  }

  /** What each function answers for [admin], given its arguments. */
  private answer(name: string, args: Row, admin: string): unknown {
    const deckOf = (id: unknown) => this.decks.find((deck) => deck.id === id);
    switch (name) {
      case "admin_overview":
        return [this.overview];
      case "admin_extractions_by_day":
        return this.extractionsByDay;
      case "admin_reported_decks":
        return this.decks
          .filter((deck) => deck.reports.length > 0)
          .map((deck) => ({
            deck_id: deck.id,
            name: deck.name,
            ...this.owner(deck),
            visibility: deck.visibility,
            hidden: deck.hidden,
            deleted: deck.deleted,
            reports: deck.reports.length,
            reasons: this.reasons(deck),
            last_reported_at: deck.reports
              .map((report) => report.at)
              .sort()
              .at(-1),
          }));
      case "admin_public_decks": {
        const search = typeof args.search === "string" ? args.search.toLowerCase() : "";
        return this.decks
          .filter((deck) => deck.visibility === "public" && !deck.deleted)
          .filter((deck) => (typeof args.owner === "string" ? deck.ownerId === args.owner : true))
          .filter((deck) => deck.name.toLowerCase().includes(search))
          .map((deck) => ({
            deck_id: deck.id,
            name: deck.name,
            ...this.owner(deck),
            hidden: deck.hidden,
            cards: deck.cards.length,
            import_count: deck.copies,
            reports: deck.reports.length,
            published_at: deck.publishedAt,
          }));
      }
      case "admin_user": {
        const user = this.users.find((candidate) => candidate.id === args.user_id);
        if (!user) return [];
        return [
          {
            id: user.id,
            email: user.email,
            created_at: user.createdAt,
            last_answer_at: user.lastAnswerAt,
            decks: user.decks,
            cards: user.cards,
            extractions_today: user.extractionsToday,
            admin: this.admins.has(user.id),
          },
        ];
      }
      case "admin_admins":
        return [...this.admins].map(([id, grant]) => ({
          user_id: id,
          email: this.users.find((user) => user.id === id)?.email ?? "",
          granted_at: grant.grantedAt,
          granted_by_email: this.users.find((user) => user.id === grant.grantedBy)?.email ?? null,
        }));
      case "admin_audit_log":
        return this.audit;
      case "admin_search_users": {
        const query = typeof args.query === "string" ? args.query.trim().toLowerCase() : "";
        if (query === "") return [];
        const matches = this.users
          .filter((user) => user.email.toLowerCase().includes(query))
          .toSorted(
            (a, b) =>
              Number(!a.email.toLowerCase().startsWith(query)) -
                Number(!b.email.toLowerCase().startsWith(query)) || a.email.localeCompare(b.email),
          );
        const offset = Number(args.page_offset ?? 0);
        return matches.slice(offset, offset + Number(args.page_size ?? 20)).map((user) => ({
          user_id: user.id,
          email: user.email,
          created_at: user.createdAt,
          suspended: this.suspensions.has(user.id),
          total: matches.length,
        }));
      }
      case "admin_user_suspension": {
        const suspension = this.suspensions.get(String(args.user_id));
        if (!suspension) return [];
        return [
          {
            reason: suspension.reason,
            suspended_at: "2026-10-19T03:00:00Z",
            suspended_by_email: this.users.find((user) => user.id === suspension.by)?.email ?? null,
          },
        ];
      }
      case "admin_suspend_user": {
        const id = String(args.user_id);
        const user = this.users.find((candidate) => candidate.id === id);
        if (!user) return "no_user";
        if (id === admin) return "self";
        if (this.suspensions.has(id)) return "already";
        const reason = String(args.reason).trim();
        this.suspensions.set(id, { reason, by: admin });
        this.record(admin, "suspend_user", "user", id, { email: user.email, reason });
        return "suspended";
      }
      case "admin_unsuspend_user": {
        const id = String(args.user_id);
        if (!this.suspensions.delete(id)) return false;
        this.record(admin, "unsuspend_user", "user", id, {
          email: this.users.find((user) => user.id === id)?.email ?? "",
        });
        return true;
      }
      case "admin_user_decks":
        return this.decks
          .filter((deck) => deck.ownerId === args.user_id && !deck.deleted)
          .map((deck) => ({
            deck_id: deck.id,
            name: deck.name,
            visibility: deck.visibility,
            hidden: deck.hidden,
            removed: this.removals.has(deck.id),
            cards: deck.cards.length,
            created_at: "2026-10-17T00:00:00Z",
          }));
      case "admin_user_deck": {
        const deck = deckOf(args.deck_id);
        if (!deck) return [];
        const removal = this.removals.get(deck.id);
        return [
          {
            id: deck.id,
            name: deck.name,
            description: deck.description,
            ...this.owner(deck),
            visibility: deck.visibility,
            hidden: deck.hidden,
            deleted: deck.deleted,
            import_count: deck.copies,
            reports: deck.reports.length,
            reasons: this.reasons(deck),
            removal_reason: removal ?? null,
            removed_at: removal === undefined ? null : "2026-10-19T03:00:00Z",
          },
        ];
      }
      case "admin_user_deck_cards": {
        const deck = deckOf(args.deck_id);
        if (!deck) return [];
        return deck.cards.map((card) => ({
          card_id: card.id,
          front: text(card.front),
          back: text(card.back),
        }));
      }
      case "admin_remove_deck": {
        const deck = deckOf(args.deck_id);
        if (!deck || this.removals.has(deck.id)) return false;
        const reason = String(args.reason).trim();
        this.removals.set(deck.id, reason);
        deck.visibility = "private";
        this.record(admin, "remove_deck", "deck", deck.id, { name: deck.name, reason });
        return true;
      }
      case "admin_prompt_versions":
        return this.prompts.toReversed().map((prompt) => this.promptRow(prompt));
      case "admin_prompt_version": {
        const prompt = this.prompts.find((candidate) => candidate.id === args.version_id);
        if (!prompt) return [];
        const active = this.prompts.find((p) => p.id === this.promptLabels.get("active"));
        return [
          {
            ...this.promptRow(prompt),
            text: prompt.text,
            active_id: active?.id ?? null,
            active_text: active?.text ?? null,
          },
        ];
      }
      case "admin_save_prompt": {
        const text = String(args.text);
        const id = (this.prompts.at(-1)?.id ?? 0) + 1;
        const note = String(args.note).trim();
        this.prompts.push({ id, text, note, by: admin });
        this.record(admin, "save_prompt", "prompt", String(id), { note, length: text.length });
        return id;
      }
      case "admin_set_prompt_label": {
        const label = args.label === "test" ? "test" : "active";
        const id = Number(args.version_id);
        const previous = this.promptLabels.get(label) ?? null;
        if (previous === id) return false;
        this.promptLabels.set(label, id);
        const cleared = label === "active" && this.promptLabels.get("test") === id;
        if (cleared) this.promptLabels.delete("test");
        this.record(
          admin,
          label === "active" ? "activate_prompt" : "test_prompt",
          "prompt",
          String(id),
          {
            previous,
            test_cleared: cleared,
          },
        );
        return true;
      }
      case "admin_clear_test_prompt": {
        const test = this.promptLabels.get("test");
        if (test === undefined) return false;
        this.promptLabels.delete("test");
        this.record(admin, "clear_test_prompt", "prompt", String(test), {});
        return true;
      }
      case "admin_plans":
        return this.plans.map((plan) => ({
          id: plan.id,
          model: plan.model,
          daily_limit: plan.daily_limit,
          updated_at: "2026-10-19T00:00:00Z",
          updated_by_email: this.users.find((user) => user.id === plan.updated_by)?.email ?? null,
        }));
      case "admin_set_plan": {
        const plan = this.plans.find((candidate) => candidate.id === args.plan);
        if (!plan || (plan.model === args.model && plan.daily_limit === args.daily_limit)) {
          return false;
        }
        this.record(admin, "set_plan", "plan", plan.id, {
          model: args.model,
          daily_limit: args.daily_limit,
          model_before: plan.model,
          daily_limit_before: plan.daily_limit,
        });
        plan.model = String(args.model);
        plan.daily_limit = Number(args.daily_limit);
        plan.updated_by = admin;
        return true;
      }
      case "admin_user_plan": {
        const user = this.users.find((candidate) => candidate.id === args.user_id);
        if (!user) return [];
        const grant = this.userPlans.get(user.id);
        const active =
          grant && (grant.endsAt === null || Date.parse(grant.endsAt) > Date.now())
            ? grant.plan
            : "free";
        const settings = this.plans.find((plan) => plan.id === active);
        return [
          {
            plan: settings?.id ?? null,
            model: settings?.model ?? null,
            daily_limit: settings?.daily_limit ?? null,
            granted_plan: grant?.plan ?? null,
            ends_at: grant?.endsAt ?? null,
            granted_at: grant ? "2026-10-19T03:00:00Z" : null,
            granted_by_email: this.users.find((u) => u.id === grant?.grantedBy)?.email ?? null,
          },
        ];
      }
      case "admin_grant_plan": {
        const id = String(args.user_id);
        if (!this.users.some((user) => user.id === id)) return "no_user";
        const endsAt = typeof args.ends_at === "string" ? args.ends_at : null;
        if (
          (args.plan !== "pro" && args.plan !== "special") ||
          (args.plan === "pro" && endsAt !== null) ||
          (endsAt !== null && Date.parse(endsAt) <= Date.now())
        ) {
          return "bad_plan";
        }
        this.userPlans.set(id, { plan: args.plan, endsAt, grantedBy: admin });
        this.record(admin, "grant_plan", "user", id, {
          email: this.users.find((user) => user.id === id)?.email ?? "",
          plan: args.plan,
          ends_at: endsAt,
        });
        return "granted";
      }
      case "admin_revoke_plan": {
        const id = String(args.user_id);
        const grant = this.userPlans.get(id);
        if (!grant) return false;
        this.userPlans.delete(id);
        this.record(admin, "revoke_plan", "user", id, {
          email: this.users.find((user) => user.id === id)?.email ?? "",
          plan: grant.plan,
        });
        return true;
      }
      case "admin_set_deck_hidden": {
        const deck = deckOf(args.deck_id);
        if (!deck || deck.hidden === args.hidden) return false;
        deck.hidden = args.hidden === true;
        this.record(admin, deck.hidden ? "hide_deck" : "unhide_deck", "deck", deck.id, {
          name: deck.name,
        });
        return true;
      }
      case "admin_unpublish_deck": {
        const deck = deckOf(args.deck_id);
        if (deck?.visibility !== "public") return false;
        deck.visibility = "private";
        this.record(admin, "unpublish_deck", "deck", deck.id, { name: deck.name });
        return true;
      }
      case "admin_dismiss_reports": {
        const deck = deckOf(args.deck_id);
        const dismissed = deck?.reports.length ?? 0;
        if (deck && dismissed > 0) {
          deck.reports = [];
          this.record(admin, "dismiss_reports", "deck", deck.id, { reports: dismissed });
        }
        return dismissed;
      }
      case "admin_grant_admin": {
        const email = typeof args.email === "string" ? args.email.trim().toLowerCase() : "";
        const user = this.users.find((candidate) => candidate.email === email);
        if (!user) return "no_user";
        if (this.admins.has(user.id)) return "already";
        this.admins.set(user.id, { grantedAt: "2026-10-19T03:00:00Z", grantedBy: admin });
        this.record(admin, "grant_admin", "user", user.id, { email });
        return "granted";
      }
      case "admin_revoke_admin": {
        const id = args.user_id;
        if (id === admin) return "self";
        if (typeof id !== "string" || !this.admins.delete(id)) return "not_admin";
        this.record(admin, "revoke_admin", "user", id, {
          email: this.users.find((user) => user.id === id)?.email ?? "",
        });
        return "revoked";
      }
      default:
        throw new Error(`the fake admin functions do not know ${name}`);
    }
  }

  readonly handlers = [
    http.post(`${supabaseUrl}/rest/v1/rpc/:name`, async ({ request, params }) => {
      const name = String(params.name);
      if (name !== "is_admin" && !name.startsWith("admin_")) return undefined;
      const user = bearerUser(request.headers.get("authorization"));
      const body = await request.text();
      const args = (body ? JSON.parse(body) : {}) as Row;
      this.calls.push(`${name} ${JSON.stringify(args)}`);
      if (name === "is_admin") {
        if (!user) {
          return HttpResponse.json(
            { code: "42501", message: "permission denied" },
            { status: 401 },
          );
        }
        return HttpResponse.json(this.admins.has(user.id));
      }
      if (!user || !this.admins.has(user.id)) {
        return HttpResponse.json(
          { code: "42501", message: "only an admin may call this" },
          { status: 403 },
        );
      }
      return new HttpResponse(JSON.stringify(this.answer(name, args, user.id)), {
        headers: { "content-type": "application/json" },
      });
    }),
  ];
}
