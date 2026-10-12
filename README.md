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
