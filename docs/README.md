# Redwave — plan documentation

Redwave is a native YouTube Music client for macOS (name chosen 2026-11-18,
see [00-prd.md](00-prd.md#1-name-and-positioning)).

Project goal: reproduce the capabilities of **YouTube Music Desktop**
(`com.github.th-ch.youtube-music` 3.12.0, the `pear-devs/pear-desktop` project, MIT)
as a native macOS app written in Swift with a fully native interface.

Status as of 2026-11-18: stages 0 and 1.1–1.3 are merged (skeleton, sign-in, InnerTube core, account switching); guest mode (1.4) is in progress.

## Contents

| File | What it covers |
|---|---|
| [00-prd.md](00-prd.md) | Product requirements: name, users, goals, functional and non-functional requirements, releases |
| [01-reverse-engineering.md](01-reverse-engineering.md) | What was found in the original app: structure, IPC, config, plugins, limits of the analysis |
| [02-architecture.md](02-architecture.md) | Architecture of the Swift version: modules, decisions, contracts between them |
| [03-roadmap.md](03-roadmap.md) | Seven development stages plus the DMG build: tasks, done criteria, checks |
| [04-plugins.md](04-plugins.md) | All 41 plugins of the original: what is ported, when and how |
| [05-risks-and-scope.md](05-risks-and-scope.md) | Risks, deliberate exclusions, open questions |
| [06-backlog.md](06-backlog.md) | Subtasks for step-by-step delivery, one pipeline run each |
| [07-designbook.md](07-designbook.md) | How the app looks: layout, colour, type, components |
| [08-ui-spec.md](08-ui-spec.md) | What every part of the interface does: data, actions, states, guest behaviour |

## The decision in one paragraph

The interface is entirely SwiftUI. Data (home, search, library, queue, likes)
comes from the InnerTube API of `music.youtube.com` using the user's cookies.
Sign-in happens on Google's page in a `WKWebView`. Audio is played by a **hidden
`WKWebView`** holding the site's player page, which Swift controls through a JS
bridge; direct audio streams and `AVPlayer` are deliberately not used
(reasons are in [02-architecture.md](02-architecture.md#3-why-audio-goes-through-a-hidden-wkwebview)).
The app is distributed as a DMG file, not through the App Store.

## Confidence labels

Facts in these documents come from different sources, and each is labelled:

- **[REA]** — obtained with REA tools from the installed artifact; has an Evidence ID.
- **[bundle]** — found by text search in the unpacked `app.asar` files.
- **[known]** — commonly known facts about InnerTube and the web player from open
  projects (ytmusicapi, youtubei.js); **not verified** in this investigation,
  to be verified at the relevant stage.
- **[decision]** — a design choice, not an observation.
