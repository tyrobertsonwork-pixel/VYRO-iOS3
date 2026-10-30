# VYRO AI Collaboration — Task Board

Use this file to hand work between Claude and ChatGPT without a paid API connection.

## How to use
1. Ty writes a task under **Ready**.
2. One assistant claims it by moving it to **In progress** and naming its branch.
3. The assistant records its changes and test results in its own log.
4. The other assistant reviews the branch/PR and records findings in its review log.
5. Ty decides whether to merge.

## Ready
- [x] First task: inspect the current VYRO app and produce a feature-preserving technical/UI audit. Audit recorded in `AI_COLLABORATION/CHATGPT_REVIEW.md` (2026-10-31).

## In progress
- [x] Streaming reliability stage 1: cancel in-flight Stremio manifest requests on timeout/player close and flush watch progress on pagehide/background. Commit: `7d5d4e07e052362d89e58fcf5dde3a370617f346`.
- [x] Streaming reliability stage 2: bounded HLS network/media recovery and one guarded native iOS HLS fallback. Commit: `1b00522464f4e9815c2cd10df11898f1b6c0f5d0`. Awaiting real-device playback verification.

## Awaiting review
_None._

## Completed
- [x] Independent technical/UI audit completed; no application code modified. Review log contains findings, test limitations and recommended implementation order.

## Rules
- Never put secrets, API keys, account credentials or signing certificates in this file.
- Include exact file paths and commit/PR links when handing off.
- Distinguish verified behavior from assumptions.
