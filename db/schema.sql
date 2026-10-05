-- Campfire schema (db/schema.rb at the frozen Campfire commit) translated to PostgreSQL.
-- Column names, nullability and defaults follow the Rails schema. SQLite's FTS5
-- message_search_index becomes a tsvector table with the same role.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE accounts (
  id bigserial PRIMARY KEY,
  created_at timestamp(6) NOT NULL,
  custom_styles text,
  join_code varchar NOT NULL,
  name varchar NOT NULL,
  settings json,
  singleton_guard integer NOT NULL DEFAULT 0,
  updated_at timestamp(6) NOT NULL
);
CREATE UNIQUE INDEX index_accounts_on_singleton_guard ON accounts (singleton_guard);

CREATE TABLE action_text_rich_texts (
  id bigserial PRIMARY KEY,
  body text,
  created_at timestamp(6) NOT NULL,
  name varchar NOT NULL,
  record_id bigint NOT NULL,
  record_type varchar NOT NULL,
  updated_at timestamp(6) NOT NULL
);
CREATE UNIQUE INDEX index_action_text_rich_texts_uniqueness ON action_text_rich_texts (record_type, record_id, name);

CREATE TABLE active_storage_blobs (
  id bigserial PRIMARY KEY,
  byte_size bigint NOT NULL,
  checksum varchar,
  content_type varchar,
  created_at timestamp(6) NOT NULL,
  filename varchar NOT NULL,
  key varchar NOT NULL,
  metadata text,
  service_name varchar NOT NULL
);
CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON active_storage_blobs (key);

CREATE TABLE active_storage_attachments (
  id bigserial PRIMARY KEY,
  blob_id bigint NOT NULL REFERENCES active_storage_blobs (id),
  created_at timestamp(6) NOT NULL,
  name varchar NOT NULL,
  record_id bigint NOT NULL,
  record_type varchar NOT NULL
);
CREATE INDEX index_active_storage_attachments_on_blob_id ON active_storage_attachments (blob_id);
CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON active_storage_attachments (record_type, record_id, name, blob_id);

CREATE TABLE active_storage_variant_records (
  id bigserial PRIMARY KEY,
  blob_id bigint NOT NULL REFERENCES active_storage_blobs (id),
  variation_digest varchar NOT NULL
);
CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON active_storage_variant_records (blob_id, variation_digest);

CREATE TABLE users (
  id bigserial PRIMARY KEY,
  bio text,
  bot_token varchar,
  created_at timestamp(6) NOT NULL,
  email_address varchar,
  name varchar NOT NULL,
  password_digest varchar,
  role integer NOT NULL DEFAULT 0,
  status integer NOT NULL DEFAULT 0,
  updated_at timestamp(6) NOT NULL
);
CREATE UNIQUE INDEX index_users_on_bot_token ON users (bot_token);
CREATE UNIQUE INDEX index_users_on_email_address ON users (email_address);

CREATE TABLE bans (
  id bigserial PRIMARY KEY,
  created_at timestamp(6) NOT NULL,
  ip_address varchar NOT NULL,
  updated_at timestamp(6) NOT NULL,
  user_id bigint NOT NULL REFERENCES users (id)
);
CREATE INDEX index_bans_on_ip_address ON bans (ip_address);
CREATE INDEX index_bans_on_user_id ON bans (user_id);

CREATE TABLE rooms (
  id bigserial PRIMARY KEY,
  created_at timestamp(6) NOT NULL,
  creator_id bigint NOT NULL,
  name varchar,
  type varchar NOT NULL,
  updated_at timestamp(6) NOT NULL
);

CREATE TABLE messages (
  id bigserial PRIMARY KEY,
  client_message_id varchar NOT NULL,
  created_at timestamp(6) NOT NULL,
  creator_id bigint NOT NULL REFERENCES users (id),
  room_id bigint NOT NULL REFERENCES rooms (id),
  updated_at timestamp(6) NOT NULL
);
CREATE INDEX index_messages_on_creator_id ON messages (creator_id);
CREATE INDEX index_messages_on_room_id_and_created_at ON messages (room_id, created_at);
CREATE INDEX index_messages_on_room_id ON messages (room_id);

CREATE TABLE boosts (
  id bigserial PRIMARY KEY,
  booster_id bigint NOT NULL,
  content varchar(16) NOT NULL,
  created_at timestamp(6) NOT NULL,
  message_id bigint NOT NULL REFERENCES messages (id),
  updated_at timestamp(6) NOT NULL
);
CREATE INDEX index_boosts_on_booster_id ON boosts (booster_id);
CREATE INDEX index_boosts_on_message_id ON boosts (message_id);

CREATE TABLE memberships (
  id bigserial PRIMARY KEY,
  connected_at timestamp(6),
  connections integer NOT NULL DEFAULT 0,
  created_at timestamp(6) NOT NULL,
  involvement varchar DEFAULT 'mentions',
  room_id bigint NOT NULL,
  unread_at timestamp(6),
  updated_at timestamp(6) NOT NULL,
  user_id bigint NOT NULL
);
CREATE INDEX index_memberships_on_room_id_and_created_at ON memberships (room_id, created_at);
CREATE UNIQUE INDEX index_memberships_on_room_id_and_user_id ON memberships (room_id, user_id);
CREATE INDEX index_memberships_on_room_id ON memberships (room_id);
CREATE INDEX index_memberships_on_user_id ON memberships (user_id);

CREATE TABLE push_subscriptions (
  id bigserial PRIMARY KEY,
  auth_key varchar,
  created_at timestamp(6) NOT NULL,
  endpoint varchar,
  p256dh_key varchar,
  updated_at timestamp(6) NOT NULL,
  user_agent varchar,
  user_id bigint NOT NULL REFERENCES users (id)
);
CREATE INDEX idx_on_endpoint_p256dh_key_auth_key_7553014576 ON push_subscriptions (endpoint, p256dh_key, auth_key);
CREATE INDEX index_push_subscriptions_on_user_id ON push_subscriptions (user_id);

CREATE TABLE searches (
  id bigserial PRIMARY KEY,
  created_at timestamp(6) NOT NULL,
  query varchar NOT NULL,
  updated_at timestamp(6) NOT NULL,
  user_id bigint NOT NULL REFERENCES users (id)
);
CREATE INDEX index_searches_on_user_id ON searches (user_id);

CREATE TABLE sessions (
  id bigserial PRIMARY KEY,
  created_at timestamp(6) NOT NULL,
  ip_address varchar,
  last_active_at timestamp(6) NOT NULL,
  token varchar NOT NULL,
  updated_at timestamp(6) NOT NULL,
  user_agent varchar,
  user_id bigint NOT NULL REFERENCES users (id)
);
CREATE UNIQUE INDEX index_sessions_on_token ON sessions (token);
CREATE INDEX index_sessions_on_user_id ON sessions (user_id);

CREATE TABLE webhooks (
  id bigserial PRIMARY KEY,
  created_at timestamp(6) NOT NULL,
  updated_at timestamp(6) NOT NULL,
  url varchar,
  user_id bigint NOT NULL REFERENCES users (id)
);
CREATE INDEX index_webhooks_on_user_id ON webhooks (user_id);

-- Replacement for SQLite FTS5 "message_search_index" (body, tokenize=porter).
-- rowid = message id, as in Campfire.
CREATE TABLE message_search_index (
  rowid bigint PRIMARY KEY,
  body text NOT NULL,
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', body)) STORED
);
CREATE INDEX index_message_search_index_on_tsv ON message_search_index USING gin (tsv);

-- Realtime: ActionCable broadcasts are stored here and delivered to browsers by
-- the polling cable shim (Goblin's host has no WebSocket or streaming support).
CREATE TABLE cable_broadcasts (
  id bigserial PRIMARY KEY,
  stream varchar NOT NULL,
  payload text NOT NULL,
  created_at timestamp(6) NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE INDEX index_cable_broadcasts_on_stream_and_id ON cable_broadcasts (stream, id);

-- Signing. Goblin has no hashing or HMAC builtins, so Rails-format signed
-- messages (base64(data) "--" hex HMAC-SHA256) are produced and checked by
-- pgcrypto. Keys are what Rails' key generator derives from secret_key_base
-- (PBKDF2-SHA256, 1000 iterations, 64 bytes) for each purpose; bin/load-seed
-- derives them once and stores them as database settings app.key_<purpose>.
-- With the same SECRET_KEY_BASE, signatures match the Rails app's exactly.
--   signed_id   ActiveRecord signed ids (avatar tokens)       urlsafe base64
--   sgid        signed global ids (mentions in rich text)    urlsafe base64, HMAC-SHA1
--   turbo       Turbo signed stream names                    strict base64
CREATE FUNCTION campfire_b64(data text, urlsafe boolean) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN urlsafe
    THEN rtrim(translate(encode(convert_to(data, 'UTF8'), 'base64'), E'+/\n', '-_'), '=')
    ELSE translate(encode(convert_to(data, 'UTF8'), 'base64'), E'\n', '') END
$$;

CREATE FUNCTION campfire_unb64(data text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT convert_from(decode(rpad(translate(data, '-_', '+/'), (length(data) + 3) / 4 * 4, '='), 'base64'), 'UTF8')
$$;

CREATE FUNCTION campfire_digest(data text, purpose text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT encode(hmac(convert_to(data, 'UTF8'), decode(current_setting('app.key_' || purpose), 'hex'),
    CASE WHEN purpose = 'sgid' THEN 'sha1' ELSE 'sha256' END), 'hex')
$$;

CREATE FUNCTION campfire_sign(data text, purpose text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT b64 || '--' || campfire_digest(b64, purpose)
  FROM (SELECT campfire_b64(data, purpose <> 'turbo') AS b64) s
$$;

CREATE FUNCTION campfire_verify(signed text, purpose text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN campfire_digest(split_part(signed, '--', 1), purpose) = split_part(signed, '--', 2)
    THEN campfire_unb64(split_part(signed, '--', 1)) END
$$;

-- Rails' signed_id(purpose: :avatar) for users.
CREATE FUNCTION campfire_avatar_token(user_id bigint) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT campfire_sign('{"_rails":{"data":' || user_id || ',"pur":"user/avatar"}}', 'signed_id')
$$;

-- User#attachable_sgid
CREATE FUNCTION campfire_user_sgid(user_id bigint) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT campfire_sign('{"_rails":{"data":"gid://campfire/User/' || user_id || '?expires_in","pur":"attachable"}}', 'sgid')
$$;

-- GlobalID#to_param and a Turbo stream name built from records and symbols.
CREATE FUNCTION campfire_gid_param(model text, id bigint) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT campfire_b64('gid://campfire/' || model || '/' || id, true)
$$;

CREATE FUNCTION campfire_signed_stream(name text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT campfire_sign(to_json(name)::text, 'turbo')
$$;

-- Time#to_fs(:number) and :epoch (milliseconds), as Campfire's views print them.
CREATE FUNCTION campfire_number(t timestamp) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT to_char(t, 'YYYYMMDDHH24MISS')
$$;

CREATE FUNCTION campfire_epoch(t timestamp) RETURNS bigint LANGUAGE sql IMMUTABLE AS $$
  SELECT floor(extract(epoch FROM t) * 1000)::bigint
$$;

CREATE FUNCTION campfire_iso(t timestamp) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT to_char(t, 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
$$;

-- Campfire stores naive UTC timestamps.
CREATE FUNCTION utc_now() RETURNS timestamp LANGUAGE sql STABLE AS $$
  SELECT (now() AT TIME ZONE 'utc')::timestamp
$$;

-- The user fields the views print (User#title, fresh_user_avatar_path, ...).
CREATE FUNCTION campfire_user_json(u users) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'id', u.id, 'name', u.name, 'bio', u.bio, 'role', u.role, 'status', u.status,
    'email_address', u.email_address,
    'title', CASE WHEN coalesce(u.bio, '') ~ '^\s*$' THEN u.name ELSE u.name || ' – ' || u.bio END,
    'avatar', '/users/' || campfire_avatar_token(u.id) || '/avatar?v=' || campfire_number(u.updated_at))
$$;

-- room_display_name needs a direct room's members; memberships order is
-- insertion order, as SQLite returns them to Rails.
CREATE FUNCTION campfire_room_json(r rooms) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'id', r.id, 'name', r.name, 'type', r.type, 'creator_id', r.creator_id,
    'updated_epoch', campfire_epoch(r.updated_at), 'updated_number', campfire_number(r.updated_at),
    'members', CASE WHEN r.type = 'Rooms::Direct' THEN (
      SELECT coalesce(json_agg(json_build_object('id', u.id, 'name', u.name) ORDER BY mb.id), '[]')
      FROM memberships mb JOIN users u ON u.id = mb.user_id WHERE mb.room_id = r.id) ELSE '[]'::json END)
$$;

-- Everything messages/_message renders, in one document per message.
-- Mentions resolve without checking the sgid signature, as Campfire's
-- attachable_from_possibly_expired_sgid does for User attachments.
CREATE FUNCTION campfire_message_json(m messages) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'id', m.id, 'client_message_id', m.client_message_id, 'creator_id', m.creator_id, 'room_id', m.room_id,
    'created_iso', campfire_iso(m.created_at), 'created_epoch', campfire_epoch(m.created_at),
    'updated_epoch', campfire_epoch(m.updated_at),
    'body', rt.body,
    'creator', (SELECT campfire_user_json(u) FROM users u WHERE u.id = m.creator_id),
    'room', (SELECT campfire_room_json(r) FROM rooms r WHERE r.id = m.room_id),
    'boosts', (SELECT coalesce(json_agg(json_build_object('id', b.id, 'content', b.content,
                 'booster', campfire_user_json(bu)) ORDER BY b.created_at, b.id), '[]')
               FROM boosts b JOIN users bu ON bu.id = b.booster_id WHERE b.message_id = m.id),
    'mentions', (SELECT json_object_agg(x.sgid, campfire_user_json(u))
                 FROM (SELECT DISTINCT (regexp_matches(rt.body, 'sgid="([^"]+)"', 'g'))[1] AS sgid) x
                 JOIN users u ON u.id = substring(campfire_unb64(split_part(x.sgid, '--', 1)) FROM 'gid://campfire/User/(\d+)')::bigint),
    'attachment', (SELECT json_build_object('id', bl.id, 'filename', bl.filename, 'content_type', bl.content_type,
                     'byte_size', bl.byte_size, 'metadata', bl.metadata,
                     'path', '/rails/active_storage/blobs/redirect/' || campfire_sign('{"_rails":{"data":' || bl.id || ',"pur":"blob_id"}}', 'signed_id') || '/' || bl.filename)
                   FROM active_storage_attachments a JOIN active_storage_blobs bl ON bl.id = a.blob_id
                   WHERE a.record_type = 'Message' AND a.record_id = m.id AND a.name = 'attachment'))
  FROM (SELECT (SELECT body FROM action_text_rich_texts WHERE record_type = 'Message' AND record_id = m.id AND name = 'body') AS body) rt
$$;
