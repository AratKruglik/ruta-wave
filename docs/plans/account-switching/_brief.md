# Brief: account-switching (backlog 1.3)

**Request:** Account list and switching for multiple Google accounts in the session.

**Backlog row (docs/06-backlog.md, 1.3):** find the endpoint and request body that `WEB_REMIX` uses for the account switcher, add the list and switch UI and the index fallback. Depends on 1.2, which is merged.

## What 1.2 established (evidence, 2026-11-18, live account)

- `account/account_menu` with `X-Goog-AuthUser: <n>` works and returns the active account's name, handle and avatar.
- `account/accounts_list` with body `requestType: ACCOUNTS_LIST_REQUEST_TYPE_CHANNEL_SWITCHER`, `callCircumstance: SWITCHING_USERS_FULL` and the `WEB_REMIX` context returns HTTP 2xx. The body holds only `responseContext` and `selectText`: no `actions` and no `accountItem`. 1.2 shipped without the list and switching (see docs/plans/innertube-core/03-qa.md, the AC13 section).
- "Add account" (`accounts.google.com/AddSession`) completes, so the session can hold two Google accounts. The user has a real second account signed in to test with.
- The Keychain item holds only the `youtube.com` cookies. The WebKit store holds the `google.com` session as well (docs/05 §2.4).

## Scope

1. **Discovery:** find a request that reliably lists the Google accounts in the cookie session together with their `authuser` indexes. Candidates for the BA and architect to weigh:
   - (a) `accounts_list` with a different body or `requestType`, the one `music.youtube.com` itself sends from its account switcher;
   - (b) probe `account_menu` with `X-Goog-AuthUser` 0, 1, 2… until an error or a repeat;
   - (c) other.

   Discovery against the live account is done by the orchestrator. It uses a temporary debug build that prints only a **redacted structure** of the response (keys, types, the `authuser` value) and never names, emails or cookies. Agents must not try to call live endpoints themselves.
2. Account list UI on the account screen with switching. The selected index persists through `AuthSession.authUserIndex`. FR15 fallback: an index that is no longer in the list goes back to 0.
3. After Add account the app stays on the current account and refreshes the list (user decision from 1.2).
4. Security note from the automated review of 1.2: replace `SignInRules.isRegionalAccountsHost` (a regex over `accounts.google.(com.|co.)?<cc>`) with Google's published supported-domains list, and allow only the `/accounts/SetSID` path on those hosts.

## Out of scope

- Brand accounts (`X-Goog-PageId`).
- Guest mode, backlog 1.4.
- Error model and paging, backlog 2.1.

## Constraints

- No real personal data in fixtures, tests, logs or docs. Synthetic data only.
- Never log cookie values or the `Authorization` header.
- The user does a manual check of the list and switching on the live account.
