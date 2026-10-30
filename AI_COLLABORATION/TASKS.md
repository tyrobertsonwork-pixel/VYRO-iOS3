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
_None._

## Awaiting review
_None._

## Completed
- [x] Independent technical/UI audit completed; no application code modified. Review log contains findings, test limitations and recommended implementation order.

## Rules
- Never put secrets, API keys, account credentials or signing certificates in this file.
- Include exact file paths and commit/PR links when handing off.
- Distinguish verified behavior from assumptions.
