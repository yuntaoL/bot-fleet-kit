---
name: Live package tracking
description: >-
  When a bot needs a package's current carrier status (FedEx, UPS, USPS, DHL,
  etc.) in near real time, e.g. inside a tracking loop, instead of waiting for
  delivery emails.
---
# Live package tracking

Goal: the freshest status the carrier itself shows, with its source and scan time. Never wait on email when a live source works.

## Source chain (try in order, stop at the first that answers)
1. **Official carrier API** if the owner has saved a key (e.g. FedEx Track API from developer.fedex.com, UPS/USPS developer APIs). Fastest and most reliable.
2. **Carrier's public tracking page in a real browser** using a computerUse subagent. Shell/curl calls to carrier endpoints are usually 403'd by bot walls, but the page loads fine in the box browser.
   - FedEx: `https://www.fedex.com/fedextrack/?trknbr=<n>`
   - UPS: `https://www.ups.com/track?tracknum=<n>`
   - USPS: `https://tools.usps.com/go/TrackConfirmAction?tLabels=<n>`
   - DHL: `https://www.dhl.com/us-en/home/tracking.html?tracking-id=<n>`
   Ask it for status, the latest scan (time, location), the delivery window, and the signature requirement. No sign-in, and change nothing.
3. **Cached tracking site over HTTP**, e.g. `curl https://www.packagetrackr.com/track/<carrier>/<n>`. Instant, but can lag tens of minutes to hours, so label it as cached.
4. **Carrier email alerts sent to a bot inbox** with a trigger on new mail. This is push-based and good for events between loops. Signing up is a form on the carrier site and needs the owner's okay.
5. **The owner's email notifications.** Last resort only.

Known dead ends from the shell, as of 2026-10: fedex.com XHR, parcelsapp, 17track, AfterShip and Ship24 (JS-only or a key is needed).

## Start time (optional)
Check as hard as the moment needs. When a request carries `startAt` (a time) and/or `startWhen` (a status trigger such as "out for delivery"), full live checks begin at whichever comes first. Before then, a light check every couple of hours from a cached source is enough, with no browser; it doesn't count toward maxChecks and is written to state only when something really changed. A delivery, an exception, or anything else the requester would act on is reported immediately even before the start. Acknowledge such requests with when checking begins, e.g. "starts <time> or on <trigger>". Use judgment: if the window is uncertain or the stakes are high (e.g. a signature is needed), start earlier.

## Reporting
- Each status line gives the state, the latest scan location and time, the delivery window, the source, and the time checked.
- Carriers show scan times in the scan location's local time. Convert them to the owner's timezone.
- Report only changes; skip repeats of the same status.
- Record what worked per carrier in your rules or memory so the next run starts with it.

## Never
Don't sign in to carrier accounts, reschedule or redirect a delivery, file claims, or contact the carrier.
