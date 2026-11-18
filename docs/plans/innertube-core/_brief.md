# Brief: innertube-core (backlog 1.2)

**Request:** InnerTube core client: WEB_REMIX context, SAPISIDHASH signing, account_menu request and account screen.

**Backlog row (docs/06-backlog.md, 1.2):** `JSONValue`, `InnerTubeClient` actor, `SAPISIDHASH` (+ vector test), `account/account_menu`, account screen with name/avatar. Depends on 1.1 (merged).

## Scope

- `InnerTube` package:
  - `JSONValue`, a dynamic JSON type for walking InnerTube responses.
  - `InnerTubeClient` actor: the `WEB_REMIX` client context, POST to `music.youtube.com/youtubei/v1/<endpoint>`, auth headers (`Authorization: SAPISIDHASH …`, `X-Goog-AuthUser`, `Origin`, `Cookie`) built from the `Auth` session.
  - `SAPISIDHASH` signing, with a known-vector unit test.
  - The `account/account_menu` request, parsed into account name, handle/email and avatar URL.
- App: an account screen in place of `SignedInPlaceholderView`. It shows the name and avatar, keeps Add account and Sign out, and adds the account list and switching that 1.1 deferred here (decision #3 in docs/plans/auth-signin/01-business-analysis.md).
- Out of scope, per docs/06-backlog.md 2.1: client version discovery from the page, paging/continuations, retry and the full error model.

## Carried over from 1.1

- The Keychain item holds only the `youtube.com` cookies and is the single source of session state. `authUserIndex` (default 0, UserDefaults) selects the account through `X-Goog-AuthUser`.
- Follow-up from the 1.1 security review (L1): reset `authUserIndex` when `restore` discards a corrupt or expired Keychain item.
- Follow-up from 1.1 QA: `AuthSession` and `KeychainItem` have no injection seam for tests. Add one only if 1.2 needs it.
- Docs to read: docs/01-reverse-engineering.md (InnerTube, auth headers), docs/02-architecture.md (InnerTube package), docs/03-roadmap.md (stage 1), docs/05-risks-and-scope.md.

## Constraints

- No real cookies, account names, emails or avatars in fixtures, tests or logs. Fixtures use synthetic data only.
- Never log cookie values or the `Authorization` header.
- A manual check by the user against the live account is expected for the account screen.
