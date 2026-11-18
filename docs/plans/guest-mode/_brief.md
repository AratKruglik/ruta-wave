# Brief: guest-mode (backlog 1.4)

**Request:** Guest mode: browse and play without signing in, optional sign-in, unauthenticated InnerTube requests.

**Backlog row (docs/06-backlog.md, 1.4):**
- The app starts without sign-in.
- `InnerTubeClient` sends unauthenticated requests (`visitorData`, no `Cookie` or `Authorization`).
- "Sign in" becomes an optional button.
- Account-only actions (library, likes, playlists) are hidden or prompt the user to sign in.

Depends on 1.2. Merged so far: 1.1, 1.2 and 1.3.

## Context

- The user asked for this on 2026-11-18. YouTube Music works without sign-in: home, explore, search and playback, with audio ads. Accepted risk #12 in docs/05 says ads are not blocked.
- Today `TunewaveApp` shows `SignInView` whenever `AuthSession.state == .signedOut`. The only signed-in screen is the account screen (`AccountView`: header plus a row of avatars for switching, Add account, Sign out).
- There is no browse, search or playback UI yet: InnerTube parsers come in 2.2–2.3, the player in 3.1–3.2, the main window shell in 4.1. So 1.4 lays the **foundation**:
  - an app state for guests;
  - unauthenticated requests in the client;
  - an optional sign-in entry point;
  - one rule that later stages follow for account-only features.
- 2.1, 4.1 and 4.5 already note in the backlog that they must also work for guests.

## Scope (to be refined by BA)

1. **App flow.**
   - Signed out means guest mode, not a forced sign-in screen.
   - Sign-in opens on request (a button) and returns to the signed-in state when it completes.
   - Cancel goes back to guest mode.
   - Sign out also goes back to guest mode.
2. **`InnerTubeClient`.** It can send a request with no credentials: no `Cookie`, no `Authorization`, no `X-Goog-AuthUser`.
   - It sends `X-Goog-Visitor-Id` once a `visitorData` value is known. The value comes from `responseContext.visitorData` of an earlier response, or from wherever BA finds it documented.
   - BA decides whether `visitorData` persists and where; it is not a secret, but it is a tracking identifier.
   - The existing signed-in path does not change.
3. **Guest screen.** A minimal placeholder until 4.1, with a clear "Sign in" button. It proves an unauthenticated request works, without building browse UI early. BA proposes the smallest check the user can see.
4. **Rule for later stages.** A single place that tells whether the user is signed in, so later screens can hide account-only actions or prompt sign-in. Record it in docs/02.

## Out of scope

- Browse, search and playback UI (2.2+, 3.x, 4.x).
- Ad blocking (rejected, risk #12).
- Changes to multi-account switching from 1.3.

## Constraints

- No personal data in fixtures, tests or logs. Never log cookies, `Authorization` or `visitorData`.
- Guest requests must never carry youtube.com cookies, even when a session exists in the Keychain.
- The user does a manual check on the live service.
