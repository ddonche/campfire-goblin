# Campfire in Goblin

This is a port of Basecamp's [ONCE Campfire](https://github.com/basecamp/once-campfire)
to [Goblin](https://github.com/ddonche/goblin-lang). It aims to behave like
the Rails app closely enough that the same HTTP tests and workload benchmarks
can run against both. The run's frozen inputs and rules are in
[EXPERIMENT.md](EXPERIMENT.md). What Goblin lacked, and how the port works
around it, is in [GAPS.md](GAPS.md).

## Status

Every route in Campfire's `config/routes.rb` is implemented:

- sign-in, first run, joining and session transfer (with QR codes)
- rooms (open, closed and direct)
- messages with rich text, mentions, sounds, boosts, editing and deleting
- attachments with thumbnails and video posters, and Active Storage's
  redirect, proxy, disk and direct-upload routes
- search, the sidebar, unread state and notification settings
- profiles, avatars, bans and the account settings: logo, custom styles,
  members, join code and bots
- the bot API, bot webhooks and link previews
- Web Push subscriptions and delivery
- the PWA manifest and service worker
- realtime updates

These were checked against the Rails app running from the same seed:

- **Benchmark pages.** The four pages the benchmarks request (room, messages
  page, sidebar, search) match Rails' output byte for byte once the host and
  the random form tokens are normalized (`bench/fetch_pages.rb`). Form tokens
  are masked the way Rails masks them, so they have the same length. The one
  remaining difference is the realtime script tag (61 bytes) on the pages
  with a layout.
- **Routes and formats.** Every GET route gives the same status and redirect
  as Rails, and the Accept-header matrix (406s for missing templates,
  `respond_to`, Turbo Stream-only actions, the manifest and the service
  worker) matches across 18 Accept values.
- **Bot API.** JSON bodies and headers match.
- **Attachments.** The image, video and file presentations match, and so do
  the blob, representation and disk redirect chains.
- **Direct uploads.** The JSON matches, as do the status codes for wrong
  type, length or checksum, and the metadata after attaching.
- **QR codes.** The SVGs match RQRCode module for module, including UTF-8
  input.
- **Webhooks.** Nine reply cases give the same message or attachment: text,
  HTML, JSON, PNG, error status, unknown type, no content, timeout and
  refused connection. The payload JSON is the same.
- **Link previews.** 27 cases give the same JSON or status. They cover
  redirects, redirect loops, private addresses, missing or invalid fields,
  charsets, gzip, entities and tags in content, and media URLs.
- **Web Push.** The configuration has no VAPID keys, so Rails never sends a
  push and there was nothing to compare against. Instead, the encrypted
  payloads were decrypted and their GCM tags verified with Ruby's OpenSSL,
  and the VAPID JWT was verified with the `jwt` gem.
- **Realtime.** `test/browser/realtime.mjs` drives two signed-in browsers
  through posting, presence and typing.

The places where behaviour still differs, and why, are listed at the end of
[GAPS.md](GAPS.md).

## How it is put together

```
browser ── nginx (:3002) ─┬─ public/ and fingerprinted assets
                          ├─ files via X-Accel-Redirect (storage/)
                          └─ everything else → goblin-host (:3102) → app/api/app.gbln
```

- **Front controller.** `app/api/app.gbln` builds the request, runs
  Campfire's authentication and CSRF before-actions (`lib/auth.gbln`) and
  dispatches through `lib/router.gbln`, which stands in for `routes.rb`, to
  `lib/controllers/*`.
- **Views.** `lib/views/*` render the same HTML as Campfire's ERB templates.
  Rich text handling is in `lib/content.gbln`.
- **Database.** Data lives in Postgres, because Goblin has no SQLite driver.
  `db/schema.sql` follows Campfire's schema and holds the SQL functions the
  app calls: signing and verification of Rails messages, JSON for views,
  search.
- **Byte, network and crypto work.** This goes through standard tools,
  called from Goblin with `:run_cmd`:
  - `bin/storage`: multipart bodies, checksums, ffprobe and ffmpeg.
  - `bin/net`: curl and getent for webhooks and link previews.
  - `bin/push`: openssl for Web Push.

  The decisions stay in Goblin, for example which addresses are public,
  what a webhook reply means, and the GCM tag.
- **Background jobs.** Rails runs webhook delivery and Web Push in Resque and
  a thread pool. Here they are `goblin run jobs/*.gbln` processes, started
  detached by the request.
- **Realtime.** goblin-host can't hold a WebSocket, so
  `cable/goblin_cable.js` carries the ActionCable protocol over POSTs and a
  long poll (`lib/controllers/cable.gbln`).

## Running it

Requirements:

- Goblin built at the commit in EXPERIMENT.md (`goblin` on `PATH`)
- Postgres with pgcrypto
- nginx
- curl, openssl, ffmpeg/ffprobe, file, getent, iconv and basenc
- Python 3, for loading seeds
- A Campfire checkout with precompiled assets, for `bin/import-assets`

```sh
# Load a benchmark seed (a directory with db/*.sqlite3), or start empty:
bin/load-seed SEED_DIR postgres://postgres@127.0.0.1:5433/campfire
bin/load-seed --empty postgres://postgres@127.0.0.1:5433/campfire

# Serve on :3002 (nginx) with goblin-host on :3102
PORT=3002 GOBLIN_PORT=3102 DATABASE_URL=postgres://postgres@127.0.0.1:5433/campfire bin/server
bin/stop
```

Environment:

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | The Postgres database. |
| `SECRET_KEY_BASE` | Read by `bin/load-seed`, which derives Rails' message keys from it. Defaults to the benchmark fixture's key, so cookies and signed ids are interchangeable with the Rails app's. |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` | Turn on Web Push, as in Rails. |
| `PORT` / `GOBLIN_PORT` | The nginx and goblin-host ports. |

For debugging, `bin/request METHOD PATH [cookie] [body]` runs one request
without a server, and `bin/signin` prints a session cookie.
