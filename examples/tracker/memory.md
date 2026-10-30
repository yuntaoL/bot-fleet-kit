# Memory – Tracker

- Fleet: slug `tracker`, role worker, manager <manager-name> (<manager-id>). Work only in worktree <wt>; save via fleet/scripts/sync.sh.
- Queue: <queue-repo>, file queue.json = JSON array of request records. Local clone <queue-clone> (git identity set per repo).
- Status sources per carrier (keep date-stamped; best first), e.g.:
  - <carrier>: API key? no · browser page `<tracking-page-url-pattern>` live (~seconds) · cached site `<cached-site-url-pattern>` (lags) · shell endpoint 403 · bot-inbox alerts: not set up
- Bot inbox for carrier alerts: <bot-inbox> (if set up).
