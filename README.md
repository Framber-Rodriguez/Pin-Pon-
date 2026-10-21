# PIN-PON

Created and directed by **Framber Rodriguez**.

[START PIN-PON](https://framber-rodriguez.github.io/Pin-Pon-/)

A neon arcade game with solo AI challenges, local two-player matches, a cinematic introduction, selectable random power-ups, object color customization, and interactive rolling credits.

## Controls

- Player 1: ↑ / ↓. Solo mode also supports W / S.
- Player 2: W / S. Space serves the ball.
- Mouse: hold and drag deliberately to move a paddle. Ordinary mouse motion or clicks do not take over keyboard controls; a gameplay key cancels an active pointer drag.
- Touch: drag a paddle. STOP pauses; RESUME continues; RESET starts over.
- CUSTOMIZE: select either paddle, the ball or the table, then choose its color.
- Credits: wheel or drag to browse. Automatic motion resumes after 1.6 seconds of inactivity and returns to the menu at the end.

## Multiball

Select Multiball in POWER-UPS to allow random ×10 pickups. Collecting one creates ten total balls with no timer. Missed balls disappear without scoring until one remains. The final surviving ball continues the rally; a point is awarded only when it is missed. All balls can collect items and use paddle collisions; the AI targets the nearest incoming ball. STOP pauses all balls; RESET and Undo clear the extras.

## Languages

English, Spanish, French, Portuguese, German, Italian, Arabic, Hindi, Chinese and Japanese. Select a language at the top right; the game remembers it. PIN-PON, creator names and provider brands stay unchanged. The cinematic video is a rendered asset and does not change language.

## Global leaderboard

Connected to the dedicated **pin-pon** Supabase project. The database, public key and redirect URLs are configured. Email authentication currently uses Supabase default delivery, restricted to project members. Public email delivery and social providers still require setup.

For another deployment: create or connect a dedicated Supabase project.
2. Run `supabase/schema.sql` in its SQL editor.
3. Put the project URL and **publishable** key (or legacy anon key) in `config.js`. Never publish a service-role key or OAuth secret.
4. Set Auth Site URL to `https://framber-rodriguez.github.io/Pin-Pon-/`. Add both the root URL and `https://framber-rodriguez.github.io/Pin-Pon-/pong.html` to allowed redirect URLs.
5. Configure custom SMTP for login emails to public players; then set `emailPublicReady: true` in `config.js`. Email magic links are enabled.
6. Enable Google, Discord or Facebook in Supabase with the provider's application credentials and the callback URL shown there. Only then add their lowercase names to `config.js` providers.

Sign in before starting a match to save its result. Categories: Easy, Normal, Hard, Very Hard, Impossible; separate Classic and Items boards. Ranked matches are solo vs AI, first to 10, 1 point per goal, no undo. Changing rules or powers during a match makes it practice. Losses are saved, but standings show players with wins. Rank sorts by wins, then cumulative winning score margin (the Points column), then earliest result. The top 50 are displayed.

Private emails never appear in public standings. Raw results live in the unexposed `pong_private` schema. Direct table access is revoked; authenticated result submission uses a constrained RPC. Public reads return display names and totals only. Duplicate match IDs are ignored and submissions are rate-limited.

**Integrity limit:** gameplay runs in the browser. These are community results, not server-verified competition scores. Authentication, database validation and rate limits do not prove that a client actually played the match. Competitive anti-cheat would require server-authoritative gameplay or replay validation.

## Development

Serve this directory with a static HTTP server (`python -m http.server 8000`). Both `index.html` and `pong.html` are supported and kept identical. No build step. Online features require HTTPS and configured Supabase.

## License

MIT. The original required copyright notice is preserved in LICENSE; the 2026 additions are credited to Framber Rodriguez.

## Online matchmaking

Open ONLINE 1v1 and select Server 1, 2 or 3. These are isolated matchmaking groups on the same Supabase backend in US East; they are not three geographically separate deployments. FIND MATCH pairs only users in the same group. CREATE ROOM generates a six-character invitation code; the friend must choose the same server before joining.

Online classic matches are first to 15, one point per goal. Both sides share ball physics and scores calculated in Postgres; browsers send only bounded paddle inputs. The online court uses your local colors. Offline customization and power-ups are unchanged; online matches use classic rules.

After a result, the loser sees VENGEANCE and the winner sees WIN AGAIN, translated into the selected language. One request waits; both requests create exactly one fresh match against the same rival, with sides swapped. Leaving declines a rematch. Requests expire after two minutes. A disconnected opponent forfeits after 15 seconds without a heartbeat; two absent players produce an abandoned match rather than a win.

The global leaderboard now has a separate Online 1v1 view per server. Online results come from server match records, not the browser's solo-result submission.

All queue, match and rematch operations require a verified non-anonymous Supabase account. Public email delivery and social-login credentials are still pending as described above; enabling the online menu does not remove that sign-in requirement.

Deployment: apply `supabase/matchmaking.sql` after the base schema. It creates private tables and bounded RPC entry points. Clients poll shared authoritative state (70 ms minimum spacing after a successful response; only one polling request in flight), interpolate snapshots for rendering, and use slower heartbeats in the queue and after results. Actual response frequency depends on network latency.

## Free-tier backend health check

[Backend health workflow](https://github.com/Framber-Rodriguez/Pin-Pon-/actions/workflows/backend-health.yml) runs daily at 14:23 UTC, on changes to its workflow file, or with **Run workflow**. It reads the three online leaderboards with the game's publishable key, validates the responses, and fails after bounded retries if the backend is unavailable. It never creates users, matches or scores. No privileged credentials are needed.

Regular database queries may help avoid Supabase free-tier inactivity pausing, but this is not an uptime guarantee and cannot resume a paused project. Resume it from the Supabase dashboard if necessary. GitHub can delay scheduled runs and automatically disables schedules in public repositories after 60 days without repository activity; re-enable the workflow in Actions when that happens. GitHub failure notifications depend on your Actions notification settings.
