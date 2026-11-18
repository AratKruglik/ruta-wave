# Brief — backlog item 1.1 (docs/06-backlog.md)

Auth package: Google sign-in in WKWebView, cookie capture to Keychain, sign-out.

Source of truth: docs/03-roadmap.md "Stage 1. Sign-in and session" (the Auth items only);
docs/02-architecture.md §1, §2, §6; docs/05-risks-and-scope.md risk #1, #8, #11 and §2.4;
docs/01-reverse-engineering.md for the original's sign-in URL and user agent.

In scope (1.1):
- `Auth` package: sign-in window with a visible `WKWebView`, Safari User-Agent, URL
  `accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&continue=…`.
- Detect successful sign-in: navigation returned to `music.youtube.com` and the cookie store
  contains `SAPISID`.
- Read the required cookies from `WKHTTPCookieStore`, store them in the Keychain.
- Session state the app can observe (signed out / signed in), restored on relaunch from Keychain.
- Sign-out: clear the Keychain items and `WKWebsiteDataStore` website data.
- Minimal app wiring: on launch, show the sign-in window when signed out; a temporary
  signed-in placeholder with a "Sign out" button.

Out of scope (1.2): InnerTube client, SAPISIDHASH, account_menu request, account name/avatar.

Go/no-go gate (docs/03 stage 1 decision point): the user signs in manually in the running app.
If Google rejects the embedded browser even with a Safari UA, stop and choose a fallback
(cookie import or ASWebAuthenticationSession) before stage 1.2. The agent never enters credentials.

Security notes carried from the 0.2 review:
- `WKWebsiteDataStore.default()` persists cookies on disk under ~/Library outside the Keychain
  — include this in the threat model (docs/05 §2.4 says cookies only in Keychain).
- Never log cookie values; no cookies in fixtures or test output.
- WKWebView: restrict navigation to Google/YouTube hosts in the navigation delegate.
