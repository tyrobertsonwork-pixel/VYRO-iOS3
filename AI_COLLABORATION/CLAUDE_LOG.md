# VYRO Development Log

## Task 1 — Streaming reliability

**Branch:** `task-1-streaming-reliability`  
**Base:** `main`  
**Status:** Implementation prepared for automated CI and review; iOS device playback remains unverified.

### Verified starting state

The repository's existing code already contained:
- A 12-second AbortController timeout in `xtreamRequest()`.
- A 20-second overall Stremio stream-discovery cancellation controller in `startStream()`.
- One-shot HLS network recovery, one-shot media recovery and a single native iOS HLS fallback in `playStream()`.
- A `pagehide` and `visibilitychange` progress flush in `flushWatchProgress()`.

These existing safeguards were retained rather than duplicated.

### Changes on this branch

1. **Local HLS.js bundle**
   - Pinned `hls.js` to 1.5.17 in `package.json`.
   - Added `scripts/copy-hls.js` to copy the installed package's minified distribution to `www/lib/hls.min.js`.
   - Changed the app to load the local asset first, retaining the CDN as a fallback.
   - Added an explicit build step to the iOS Actions workflow so the asset is present before Capacitor sync/build.

2. **Bounded JSON request timeout and retries**
   - Added `requestJsonWithRetry()`, which keeps the timeout active while reading the response body.
   - Retries transient HTTP statuses (408, 425, 429, 500, 502, 503, 504) and network/timeout failures with bounded backoff.
   - Does not retry ordinary client errors such as 401, 403 or 404.
   - Respects a caller-provided AbortSignal and removes its listener/timer after each attempt.

3. **TMDB**
   - TMDB JSON calls now use a 10-second per-attempt timeout and at most two retries.
   - Existing cache and in-flight request deduplication are preserved.

4. **Stremio add-ons**
   - Manifest tests use an 8-second per-attempt timeout and one retry.
   - Individual stream endpoint calls use the same bounded timeout/retry policy.
   - The existing 20-second overall stream lookup cancellation remains authoritative; cancellation now propagates out of the per-source loop instead of being treated as an ordinary source failure.

5. **Automated checks**
   - Added `tests/streaming-reliability-smoke.cjs` to check the pinned dependency, local HLS entry point, retry policies, cancellation propagation and retained HLS/progress recovery safeguards.
   - Added the check to the existing iOS Actions workflow.

### Files changed

- `www/index.html`
- `package.json`
- `scripts/copy-hls.js` (new)
- `tests/streaming-reliability-smoke.cjs` (new)
- `.github/workflows/ios-unsigned-ipa.yml`

### Validation status

The repository changes have been prepared through GitHub's file/branch operations. The GitHub Actions workflow is configured to run:
- Node JavaScript syntax validation (`node --check`)
- Existing responsive layout/navigation smoke tests
- New streaming reliability smoke tests
- Capacitor iOS sync and unsigned IPA build

**Not yet verified:** The workflow has not yet been observed completing, and no on-device iOS playback/network-failure test has been performed. Do not treat the implementation as device-verified or merge-ready until CI and device checks pass.

### Review notes

- CapacitorHttp is already enabled in `capacitor.config.ts`; this change does not claim that native request cancellation semantics have been proven on-device.
- HLS.js is bundled into the app during the build; a normal repository checkout does not contain the generated minified bundle until `npm run build` runs.
- Xtream's existing request behavior and timeout were left unchanged to avoid changing provider login/rate-limit behavior.
