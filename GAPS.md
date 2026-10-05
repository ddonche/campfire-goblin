# Where Goblin falls short, and what the port does about it

None of these stopped the port. Every Campfire feature runs, but a few run
through standard command-line tools or a different transport because Goblin
has no built-in way to do the job. Each entry below covers what is missing,
why Campfire needs it, what the port does instead, and the smallest
general-purpose addition to Goblin that would remove the workaround.

Goblin, goblin-host and Sheriff were not modified. Short scripts that show
the interpreter problems are in [`docs/goblin-repros/`](docs/goblin-repros/).
Run them with `goblin run` from that directory.

## Missing capabilities

### 1. Long-lived connections (WebSocket) in goblin-host

**Why Campfire needs it.** ActionCable over a WebSocket carries new messages,
presence, typing indicators, unread badges and room list updates.

**What goblin-host does.** It runs one short-lived `goblin` process per
request and returns one response. It cannot upgrade a connection or keep one
open.

**What the port does.** `cable/goblin_cable.js` stands in for the browser's
`WebSocket` on `/cable`. It speaks the ActionCable protocol over JSON POSTs,
and broadcasts arrive through a 20-second long poll
(`lib/controllers/cable.gbln`). Broadcasts are rows in `cable_broadcasts`.
The page loads one extra script, so the realtime transport differs from
Rails. Message rendering and stream names are the same.

**Smallest addition.** WebSocket upgrade in goblin-host: hand an upgraded
connection to a script that can `:ws_receive` and `:ws_send` until it closes.
A host-level pub/sub primitive, letting a script block on a channel, would
also replace the polling table.

### 2. SQLite

**Why Campfire needs it.** Campfire stores everything in SQLite, including an
FTS5 index for search. The benchmark seeds are SQLite files.

**What the port does.** It runs on Postgres, using Goblin's `db_*` builtins.
`bin/load-seed` copies a seed's SQLite database, including the search index
rows, into Postgres, so the same seed drives both apps. The search index is
a Postgres text-search table, with a stemming setup that mirrors FTS5's
porter tokenizer.

**Smallest addition.** `:sqlite_query`/`:sqlite_exec` builtins mirroring the
Postgres ones, with FTS5 compiled in.

### 3. Bytes and binary files

**Why Campfire needs it.** Uploads, avatars, logos, video posters,
checksums, multipart bodies and Web Push payloads all handle raw bytes.

**What Goblin does.** Strings are UTF-8 text. `:read_text` fails on binary
data, and there is no byte type.

**What the port does.**
- `bin/storage` handles byte work with `file`, `openssl md5`, `ffprobe` and
  `ffmpeg`: slicing multipart bodies, MD5 checksums, image and video metadata,
  and variants.
- Files are served by nginx through `X-Accel-Redirect`.
- Values cross between Goblin and the tools as hex or as files.

**Smallest addition.** A bytes value, with `:read_bytes`/`:write_bytes`,
indexing and slicing, and hex and base64 conversion.

### 4. Hashing, HMAC, base64 and other cryptography

**Why Campfire needs it.** Rails' signed cookies, signed ids, signed global
ids, Active Storage URLs, password digests, MD5 checksums, the VAPID
signature and Web Push encryption.

**What the port does.**
- Postgres' pgcrypto handles HMAC-SHA1/SHA256, SHA-256, bcrypt and base64
  (see the signing functions in `db/schema.sql`).
- Rails' PBKDF2 key derivation runs once, at setup, in `bin/load-seed`.
- `bin/push` uses `openssl` for ECDH, HKDF, AES block encryption and ES256
  signatures.
- AES-GCM's GHASH is written in Goblin (`lib/webpush.gbln`), because the
  `openssl` command line has no AEAD mode.

**Smallest addition.** `:sha256`, `:sha1`, `:md5`, `:hmac(alg, key, data)`,
`:base64_encode/decode` and `:random_bytes`, given a bytes value. Web Push
would also need `:aes_gcm_encrypt` and P-256 `:ecdh`/`:ecdsa_sign`, or one
binding to a crypto library.

### 5. HTTP client and DNS

**Why Campfire needs it.** Bot webhooks (`Webhook#deliver`), link previews
(`Opengraph::Fetch`, with every redirect checked against private networks)
and Web Push delivery.

**What the port does.**
- `bin/net` and `bin/push` call `curl`, one request at a time, pinned to an
  address that Goblin has already checked (`--resolve`).
- Addresses come from `getent ahosts`.
- The private-network policy, a port of the surfguard gem, is written in
  Goblin in `lib/opengraph.gbln`.

**Smallest addition.** `:http_request(method, url, headers, body, options)`
returning status, headers and body. The options would include timeouts,
redirect following off, a pinned address and no proxy. A
`:resolve_host(name)` would return all addresses.

### 6. Bitwise operators

**Why Campfire needs it.** QR codes (Reed-Solomon over GF(256), masks, BCH
format bits) and the GF(2^128) multiplication in AES-GCM.

**What the port does.** XOR goes through a 16×16 nibble table; shifts and
bit tests use integer division.

**Smallest addition.** `&`, `|`, `^`, `<<`, `>>` on integers.

### 7. A character from a code point

**Why Campfire needs it.** Numeric HTML entities in link previews (`&#8217;`)
and URL decoding.

**What the port does.** It uses `:json_parse("\"\\uXXXX\"")`, with
surrogate pairs above U+FFFF.

**Smallest addition.** `:chr(n)`, the inverse of `:ord`.

### 8. Background work

**Why Campfire needs it.** Webhook delivery and Web Push run outside the
request: Resque jobs and a thread pool in Rails.

**What the port does.** The request writes a job file and starts
`setsid goblin run jobs/<name>.gbln … &` through `:run_cmd`. The job imports
the app's modules and talks to Postgres directly.

**Smallest addition.** A `:spawn(script, env)` builtin that starts a detached
script, or a job queue in goblin-host.

### 9. Images and video

Rails resizes with libvips and takes video posters with ffmpeg. The port uses
ffmpeg for both, so variants have the same type and dimensions as Rails' but
different bytes. This is not really a Goblin gap; an image library would be a
separate project.

## goblin-host behaviour that shows through

- **Content-Type on every response.** A 204 or 304 still carries a
  Content-Type (`text/plain` by default), where Rack sends none.
- **Bodiless responses carry one byte.** An empty body makes the CLI print no
  envelope at all, so the port sends one space. That stray byte would corrupt
  the next response on a reused upstream connection, so nginx does not keep
  upstream connections alive.
- **Fixed headers.** `x-goblin-web-contract`, `Referrer-Policy`,
  `X-Content-Type-Options` and `X-Frame-Options` are added to every response,
  including Active Storage's proxy responses, which in Rails have none of
  them.
- **Request bodies are never deleted.** Every body is written to
  `/tmp/goblin-request-*` and left there. The port deletes the file after each
  request (`app/api/app.gbln`).
- **No routing, and responses are text.** nginx maps every request to the
  front controller (`app/api/app.gbln`) and serves files and assets itself.
- **One process per request.** Every request starts an interpreter and
  imports the app. Single requests to the four benchmark pages took
  130–290 ms here, against 20–70 ms for Rails. These are rough numbers from
  one sequential client, not the benchmark.

**Smallest additions.** Leave out Content-Type when a script sets none, allow
a truly empty body, make the default headers configurable, delete the
request file after the script exits, and keep a warm interpreter with
imported modules cached between requests.

## Interpreter problems met along the way

Each one has a workaround in the port. The repro scripts show them in a few
lines each.

| Problem | Repro | Workaround in the port |
|---|---|---|
| A local declared inside a `while` body breaks later assignments in that loop with `R0000 internal: const table missing entry` | `while_local.gbln` | `for` over a list of indexes |
| Reassigning a `for` variable that came from `:split`, in a nested loop, fails the same way | `for_variable_reassign.gbln` | assign to a new name |
| `:chars` yields numbers for digit characters, so string builtins reject them (`T0205`) | `chars_digits.gbln` | wrap in `:str` |
| `s[:len(x) + i:]` parses as a slice up to `len(x)+i`, and `s[0::find(...)]` as a module path. `list[0:at]` (a variable after the colon) and indexing a call's result inside another call's arguments fail to parse too (P0508) | `slice_parse.gbln` | compute the index first; loops instead of slices |
| Reassigning an act's parameter (`c |= ...`) fails with the same `const table missing entry` in some call paths. It didn't reproduce in a small script | — | assign to a new name |
| An imported module's constants can't be read (`m::NAME` gives "unknown enum") | `module_constant.gbln` | accessor acts |
| `:range` is not available in the interpreter | `range.gbln` | small `upto`/`span` acts |
| `blob` and `stop` can't be used as variable names (P1101, R0405) | `keyword_blob.gbln`, `keyword_stop.gbln` | other names |
| Maps keep their keys sorted, so JSON loses Rails' key order | — | `lib/ojson.gbln` |
| Updating a list element copies the list, so grid algorithms go quadratic | — | rows as separate lists. The QR encoder went from about 105 s to seconds, and codes are cached on disk |
| The regex engine has no lookahead or backreferences | — | two-step matches |
| The VM (`--vm`) can't compile the port: `:update!` on a nested or module-qualified index fails, and module globals are uninitialized | — | the port runs on the interpreter, as goblin-host does |

## Remaining differences from Rails

Each item is listed under its cause above.

- **Realtime transport.** It is long polling, not a WebSocket (section 1).
- **Image variant bytes.** They come from ffmpeg, not vips (section 9).
- **Active Storage variation digest.** Rails digests a Marshal dump. The
  port digests the variation's JSON, and only the port reads it.
- **Webhook timeout.** Rails' 7-second read timeout restarts with every
  read. Here the whole exchange must finish within 7 seconds, because curl has
  no per-read timeout.
- **Named entities in link previews.** Numeric entities are all decoded.
  Named entities cover the common ones (`&amp;`, quotes, dashes, accented
  Latin letters), not the full HTML5 table.
- **Link previews of tweets.** When fxtwitter.com returns nothing, Rails
  raises (a 500) and the port answers 204.
- **Headers on bodiless responses.** 204/304 responses carry a Content-Type,
  and Active Storage proxy responses carry goblin-host's fixed headers. A 406
  has a one-byte body where Rails' is empty.
- **Form tokens.** Rails masks a per-form token (an HMAC of the form's
  action) with a fresh pad for every form. The port masks the session's
  token once per request and uses it for every form. Lengths are the same
  and both kinds verify, but the bytes differ (section 4: the masking runs in
  Postgres). Rails' cached message fragments also keep the token of whoever
  rendered them first.
- **Format extensions.** `/webmanifest.json` and `/service-worker.js` work,
  but other paths with a format extension (`/rooms/1.json`) give a 404 where
  Rails would answer 406.
