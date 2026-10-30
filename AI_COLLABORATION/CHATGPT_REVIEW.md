# ChatGPT — VYRO Review Log

ChatGPT: record independent reviews and feedback here.

For each review include:
- Date
- Task/PR/commit reviewed
- Files inspected
- Findings, ordered by severity
- Specific suggested fixes
- Tests or checks performed
- Approval recommendation: approve / request changes / needs manual testing

Do not claim to have run a build, simulator, or device test unless that actually happened.

---

_No review recorded yet._


## Review — 2026-10-31

### Task
Independent feature-preserving technical/UI audit of the current VYRO app. Reviewed branch `ai-collaboration`; no application code changed.

### Files inspected
- `README.md`
- `package.json`
- `capacitor.config.ts`
- `.github/workflows/ios-unsigned-ipa.yml`
- `www/index.html` (full 2,868-line file)
- `tests/layout-smoke.cjs`
- `AI_COLLABORATION/PROJECT_BRIEF.md` and `AI_COLLABORATION/TASKS.md`

### Verified current implementation
- Single-page HTML/CSS/JavaScript app in `www/index.html`, packaged with Capacitor 7 for iOS WKWebView. App ID is `app.vyro.cinema`.
- UI includes Home, Discover, My List and Settings; responsive poster/catalogue rails; detail and cast/person views; local saved list and watch-progress persistence; TMDB-powered trending/discover/search/details; Stremio-compatible VOD manifest lookup; Xtream login/catalogue/movie/series/episode paths; HTML5 video playback with optional HLS.js.
- TMDB, Stremio add-ons and Xtream functionality are client-side integrations, not a complete backend or native streaming stack. Playback depends on provider response formats, CORS/network access, supported codecs and iOS WebKit.
- `CapacitorHttp` is enabled in `capacitor.config.ts`, but the inspected app code uses browser `fetch()`; no use of the native HTTP bridge was found in the app script. Do not assume that setting currently bypasses WebView CORS.
- App settings, My List and watch progress use localStorage. The TMDB key and Xtream username/password are also persisted there by the settings implementation. This is a significant device-local credential exposure consideration; there is no account sync or secure credential vault in the inspected code.
- HLS.js is loaded from jsDelivr at runtime. The UI has no visible fallback guarantee if the CDN is unavailable; iOS native HLS behavior differs from the HLS.js branch.
- README currently says real streaming/add-ons are not integrated. That description is stale relative to the code: integration paths exist, but they are conditional and not verified end-to-end. README should distinguish implemented client-side connection flows from verified production playback.

### Findings — highest priority first
1. **Credential handling (high):** `www/index.html` stores TMDB and Xtream credentials in localStorage. Any script executing in the WebView origin can read them; there is no secure storage or backend proxy. Before production use, remove plaintext persistence for provider passwords, consider a supported secure-storage approach, and document the TMDB key's exposure/rate-limit implications. Never add credentials to Git.
2. **Network/CORS and provider compatibility (high):** Stremio manifest and stream lookup and Xtream requests use `fetch()`. The code itself acknowledges provider CORS restrictions. Enabling `CapacitorHttp` in config alone does not prove these calls use native networking. Test actual providers on-device and implement a deliberate native networking path or backend proxy where legally and technically appropriate.
3. **Playback reliability (high):** HTML5 video supports only formats/codecs available to iOS WebKit; the app detects some likely unsupported extensions and has HLS.js handling, but this is not equivalent to broad format support. Validate MP4/HLS, redirects, headers, subtitles, audio tracks, seek, resume, and errors on real iPhones. Avoid claiming universal playback.
4. **External runtime dependency (medium):** HLS.js is CDN-loaded with no bundled/offline fallback or Subresource Integrity attribute. A CDN outage, content change, or network restriction can affect HLS playback. Pinning the version is good, but bundling and testing the dependency would be more robust.
5. **No application-level automated functional suite (medium):** The workflow checks inline JavaScript syntax and required element IDs, then runs Playwright responsive-layout/navigation/overlay smoke tests across six viewport sizes. The current test does not exercise real TMDB responses, add-on manifests, Xtream authentication/catalogue, video playback, persistence recovery, or iOS WKWebView behavior.
6. **Build reproducibility (medium):** `package.json` has no lockfile shown in the inspected root and the workflow uses `npm install`; dependency resolution can drift. Prefer committing `package-lock.json` and using `npm ci`. The workflow produces an unsigned IPA only; signing/install compatibility remains a separate step.
7. **Accessibility and native feel (medium):** There are useful focus-visible styles, reduced-motion handling, labels on several controls and safe-area support. However, much of the interaction is custom DOM/CSS in one large document; a dedicated pass is needed for VoiceOver labels/order, dynamic status announcements, contrast, text scaling, keyboard focus restoration, and modal focus management. The visual direction is still a web implementation in WKWebView, not a native SwiftUI interface; design polish alone cannot make it fully native.
8. **Maintainability (medium):** The 112 KB / 2,868-line HTML file combines markup, styling, state, API clients, rendering and player logic. Split into focused modules/styles and add regression tests incrementally rather than replacing the whole file.

### Recommended implementation order
1. Preserve this baseline and create a clean feature inventory/regression checklist.
2. Resolve credential storage and decide the supported networking architecture (native Capacitor HTTP bridge vs secure backend proxy), then test on iPhone.
3. Establish real playback acceptance tests for known legal test streams and supported formats; improve diagnostics and fallback behavior.
4. Make builds reproducible with a lockfile and `npm ci`; expand Playwright tests for saved list, settings, search, details and error states.
5. Refactor the monolithic file in small, behavior-preserving steps; then do the premium iOS interaction/VoiceOver pass.
6. Update README so it accurately describes current client-side integration paths and their unverified limitations.

### Tests/checks performed
- Read the repository workflow and test source. The workflow is configured to run `node --check` on the extracted inline script and `tests/layout-smoke.cjs` across 320, 375, 393, 430, 768 and 1024 px viewports.
- Did **not** execute GitHub Actions, npm install, Playwright, xcodebuild, an iOS simulator, or a physical-device test in this review. Therefore no build or runtime test is claimed as passed.

### Approval recommendation
**Needs manual testing.** No app code changed. The current branch is suitable for a carefully staged next implementation, but credential handling, real provider connectivity and playback must be validated before describing VYRO as production-ready.

### What to review next
Ty should approve one focused next task. Recommended first engineering task: add a reproducible baseline test run and document the exact iPhone/provider playback failures before changing networking or credentials. Keep the existing feature set intact.


## Streaming reliability — stage 1 — 2026-10-31

### Branch and commit
- Branch: `ai-collaboration`
- Commit: `7d5d4e07e052362d89e58fcf5dde3a370617f346`

### File changed
- `www/index.html`

### Changes
- Added a dedicated AbortController for Stremio stream discovery.
- Passed its signal to each add-on manifest stream request so a timed-out lookup or closing/replacing the player cancels outstanding network requests rather than leaving them running.
- Kept the existing 20-second lookup limit and changed it to abort the underlying requests at timeout.
- Kept the existing HTTP/HTTPS stream URL validation unchanged.
- Added a `pagehide` and document-hidden flush for watch progress; existing five-second persistence and player-close flush remain.

### Checks actually run
- Retrieved the committed HTML from `ai-collaboration` after the commit.
- Extracted the inline application script and compiled it with JavaScript `new Function`: PASS (one inline application script).
- Targeted source assertions: controller state, timeout abort, player-close abort, pagehide and visibility flush all present.
- The first signal regex assertion was too strict and returned false; direct source inspection confirms `{ headers: { Accept: 'application/json' }, signal }` is present in the manifest fetch.
- No GitHub Actions run, npm install, Playwright, Xcode build, simulator or physical iPhone playback test was run. No runtime success is claimed.

### Remaining work
- Add bounded HLS fatal-error recovery and carefully test native HLS fallback.
- Decide on local HLS.js bundling only after checking package/dependency/build impact.
- Verify on an actual iPhone with known legal MP4/HLS test sources and the user's configured provider.

### Approval recommendation
Needs manual iPhone testing; this is a focused reliability improvement, not a complete streaming fix.


## Streaming reliability — stage 2 — 2026-10-31

### Branch and commit
- Branch: `ai-collaboration`
- Commit: `1b00522464f4e9815c2cd10df11898f1b6c0f5d0`

### File changed
- `www/index.html`

### Changes
- Added one bounded retry for fatal HLS network errors using `startLoad()`.
- Added one bounded decoder recovery attempt for fatal HLS media errors using `recoverMediaError()`.
- If HLS.js recovery remains fatal and WebKit advertises native HLS support, destroy the HLS.js instance and attempt the same stream URL through the native iOS video element once.
- Kept the existing player preference behavior and existing non-HLS playback path.

### Checks actually run
- Fetched the updated committed HTML from `ai-collaboration`.
- Compiled the inline app script with JavaScript `new Function`: PASS.
- Targeted source checks for abort-signal propagation, 20-second abort, HLS network recovery, media recovery, native HLS fallback and pagehide persistence: all PASS.
- No HLS.js runtime simulation, GitHub Actions run, iOS build, simulator or physical iPhone test was performed. The fallback is implemented but remains unverified on-device.

### Remaining
- Local HLS.js bundling is not included yet; current CDN dependency remains.
- Provider-specific CORS, auth headers, redirects, codecs and actual playback require device testing.
