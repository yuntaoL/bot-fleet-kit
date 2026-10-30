# Example: Tracker

A worker bot that other bots hand "keep checking X until Y" jobs to (first use: package tracking).

- **Queue:** `queue.json` in a private git repo you create (your private queue repo). Pushed only on change; finished requests are removed and summarized in the commit message.
- **Loop:** one routine every ~15 min; pauses itself when the queue is empty, resumes on a new request.
- **Future list:** `future.json` in the same repo holds requests with a later `startAt`; `tracker-future` runs hourly in check hours, moves due ones into `queue.json` and resumes the loop, and pauses itself when empty. Saves tokens by not polling items that haven't started.
- **Per request:** expected status, `expiresAt`, `maxChecks` (defaults 14 days / 1000), dedupe by target.
- **Results** go only to the requesting bot (priority), never to the user or outsiders.
- **Status-source chain** (near-real-time first): carrier API (if you have a key) → carrier tracking page in a real browser subagent (shell calls often get 403s) → cached tracking site over HTTP (may lag minutes to hours) → carrier email alerts to a bot inbox that triggers on new mail → the user's email notifications (last resort). Each status is reported with its source and scan time; email is never waited on when a live source works.

Skill: [`skills/live-package-tracking/SKILL.md`](skills/live-package-tracking/SKILL.md), the reusable method behind the chain.

Placeholders to fill: `<wt>`, `<me>`, `<manager-name>`, `<manager-id>`, `<queue-repo>`, `<queue-clone>`, `<timezone>`, `<platform-id>`, and the minute offsets in `routines/tracker-loop.json`, and the minute and check hours in `routines/tracker-future.json`. Needs: git access to the queue repo; a browser/computerUse subagent for step 2; optionally a carrier API key, a bot inbox, and read-only mail access for steps 4–5. Extra placeholders: `<bot-inbox>`, `<carrier>`, URL patterns in memory.md.

Sample queue entry:
```json
{ "id": "pkg-001", "requester": {"name": "Assistant", "id": "<bot-id>"}, "check": {"carrier": "UPS", "tracking": "<tracking-number>"},
  "expected": "Delivered", "expiresAt": "<iso>", "maxChecks": 1000, "checkCount": 0, "lastStatus": null, "createdAt": "<iso>", "updatedAt": "<iso>" }
```
