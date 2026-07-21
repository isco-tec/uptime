# uptime

Standing uptime + correctness monitoring for every production surface in the
portfolio. Runs on GitHub Actions every 15 minutes — no servers, no external
accounts, free on a public repo.

## What it checks (better than a ping)

For each site in [sites.json](sites.json):

1. **Liveness** — HTTP status < 400 (< 500 for `api: true` endpoints, whose
   roots legitimately 404)
2. **Redirect sanity** — following redirects must land on the site's own host
   (or an explicitly `allow_hosts` one). *This catches the failure a status
   ping can't: a site returning a healthy 200 while serving the wrong product —
   which actually happened to api.intentrun.art for ~3 months.*
3. **Content sanity** — the response body must contain the brand's expected
   substring (case-insensitive)

## Alerting

A failing check opens a GitHub issue (label `uptime`) titled
`🔴 <host> check failing`; it closes itself with a ✅ comment on recovery.

**To get emailed:** Watch this repo (Watch → All activity), and make sure
GitHub notification emails are enabled for issues. That's the whole alert stack.

## Operating it

- **Add/remove a site:** edit [sites.json](sites.json). Keep it in sync with the
  domain inventory at `~/Code/ccc/infrastructure/domains.md` (source of truth).
- **Run locally:** `./scripts/check.sh`
- **Run now (CI):** Actions → Uptime → Run workflow
- **Deeper investigation:** the `portfolio-ops-sweep` Claude skill does the
  richer in-session version (TLS expiry, VPS host state via the vps-devops
  agent); this repo is the between-sessions safety net.

## Notes

- **Public** since 2026-07-21 (cost audit): Actions minutes are free, cadence is
  `*/15`. Verified before flipping: full history contains only public URLs and
  brand words; run logs show only OK/FAIL lines with runner-masked tokens; alert
  issues carry no internal paths.
- Flappy sites: curl already retries twice per check. If a site flaps, consider
  raising `-m 20` or requiring two consecutive failures before alerting.
