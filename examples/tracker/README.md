# Example: Tracker

A worker bot that other bots hand "keep checking X until Y" jobs to (first use: package tracking).

- **Queue:** `queue.json` in a private git repo you create (your private queue repo). Pushed only on change; finished requests are removed and summarized in the commit message.
- **Loop:** one routine every ~15 min; pauses itself when the queue is empty, resumes on a new request.
- **Per request:** expected status, `expiresAt`, `maxChecks` (defaults 14 days / 1000), dedupe by target.
- **Results** go only to the requesting bot (priority), never to the user or outsiders.
- **Fallback:** when a carrier blocks scripted tracking, a read-only email search for delivery notices.

Placeholders to fill: `<wt>`, `<me>`, `<manager-name>`, `<manager-id>`, `<queue-repo>`, `<queue-clone>`, `<timezone>`, `<platform-id>`, and the minute offsets in `routines/tracker-loop.json`. Needs: git access to the queue repo; optional read-only mail access for the fallback.

Sample queue entry:
```json
{ "id": "pkg-001", "requester": {"name": "Assistant", "id": "<bot-id>"}, "check": {"carrier": "UPS", "tracking": "<tracking-number>"},
  "expected": "Delivered", "expiresAt": "<iso>", "maxChecks": 1000, "checkCount": 0, "lastStatus": null, "createdAt": "<iso>", "updatedAt": "<iso>" }
```
