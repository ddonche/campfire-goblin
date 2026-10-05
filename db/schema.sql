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
  content varchar NOT NULL, -- limit: 16 in schema.rb, which SQLite does not enforce
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
-- FTS5's porter tokenizer stems but keeps stop words, so the search
-- configuration is English stemming without the stop-word list.
CREATE TEXT SEARCH DICTIONARY campfire_stem (TEMPLATE = snowball, LANGUAGE = english);
CREATE TEXT SEARCH CONFIGURATION campfire (COPY = english);
ALTER TEXT SEARCH CONFIGURATION campfire
  ALTER MAPPING FOR asciiword, asciihword, hword_asciipart, word, hword, hword_part WITH campfire_stem;

CREATE TABLE message_search_index (
  rowid bigint PRIMARY KEY,
  body text NOT NULL,
  tsv tsvector GENERATED ALWAYS AS (to_tsvector('campfire', body)) STORED
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

-- Message.create! with its callbacks: the rich text body, touching the room,
-- Room#receive's unread marks, and the search index row. Returns the
-- message as campfire_message_json and the room's member ids for the
-- unread-room fan-out.
CREATE FUNCTION campfire_create_message(p_creator bigint, p_room bigint, p_body text, p_client text, p_plain text)
RETURNS json LANGUAGE plpgsql AS $$
DECLARE
  m messages;
  ts timestamp := utc_now();
BEGIN
  INSERT INTO messages (client_message_id, created_at, creator_id, room_id, updated_at)
  VALUES (coalesce(nullif(p_client, ''), gen_random_uuid()::text), ts, p_creator, p_room, ts)
  RETURNING * INTO m;
  IF p_body IS NOT NULL THEN
    INSERT INTO action_text_rich_texts (body, created_at, name, record_id, record_type, updated_at)
    VALUES (p_body, ts, 'body', m.id, 'Message', ts);
  END IF;
  UPDATE rooms SET updated_at = ts WHERE id = p_room;
  UPDATE memberships SET unread_at = m.created_at, updated_at = ts
  WHERE room_id = p_room AND involvement <> 'invisible' AND user_id <> p_creator
    AND (connected_at IS NULL OR connected_at < ts - interval '60 seconds');
  INSERT INTO message_search_index (rowid, body) VALUES (m.id, coalesce(p_plain, ''));
  RETURN json_build_object(
    'message', campfire_message_json(m),
    'member_ids', (SELECT coalesce(json_agg(user_id ORDER BY id), '[]') FROM memberships WHERE room_id = p_room));
END $$;

-- ---------- ActionCable over long polling ----------
-- The stream an ActionCable subscription identifier streams from for a user,
-- applying each channel's `subscribed` authorization: '' for a channel that
-- streams nothing (HeartbeatChannel), NULL for a rejected subscription.
CREATE FUNCTION campfire_cable_stream(p_user bigint, p_identifier text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  ident json;
  channel text;
  name text;
  gid text;
  room rooms;
BEGIN
  BEGIN
    ident := p_identifier::json;
    channel := ident->>'channel';
  EXCEPTION WHEN others THEN
    RETURN NULL;
  END;

  IF channel IN ('Turbo::StreamsChannel', 'RoomMessagesChannel') THEN
    BEGIN
      name := campfire_verify(ident->>'signed_stream_name', 'turbo')::json #>> '{}';
    EXCEPTION WHEN others THEN
      RETURN NULL;
    END;
    IF name IS NULL THEN RETURN NULL; END IF;
    -- RoomMessagesChannel.guarded_stream?: the part after the first colon is "messages"
    IF channel = 'Turbo::StreamsChannel' THEN
      RETURN CASE WHEN position(':' IN name) > 0 AND substr(name, position(':' IN name) + 1) = 'messages' THEN NULL ELSE name END;
    END IF;
    IF position(':' IN name) = 0 OR substr(name, position(':' IN name) + 1) <> 'messages' THEN RETURN NULL; END IF;
    BEGIN
      gid := campfire_unb64(split_part(name, ':', 1));
    EXCEPTION WHEN others THEN
      RETURN NULL;
    END;
    SELECT r.* INTO room FROM rooms r JOIN memberships m ON m.room_id = r.id AND m.user_id = p_user
    WHERE gid ~ '^gid://campfire/(Room|Rooms::Open|Rooms::Closed|Rooms::Direct)/[0-9]+$'
      AND r.id = substring(gid FROM '([0-9]+)$')::bigint;
    RETURN CASE WHEN room.id IS NULL THEN NULL ELSE name END;
  END IF;

  IF channel IN ('PresenceChannel', 'TypingNotificationsChannel') THEN
    IF coalesce(ident->>'room_id', '') !~ '^[0-9]+$' THEN RETURN NULL; END IF;
    SELECT r.* INTO room FROM rooms r JOIN memberships m ON m.room_id = r.id AND m.user_id = p_user
    WHERE r.id = (ident->>'room_id')::bigint;
    IF room.id IS NULL THEN RETURN NULL; END IF;
    -- stream_for @room: "<channel_name>:<room gid param>"
    RETURN CASE channel WHEN 'PresenceChannel' THEN 'presence' ELSE 'typing_notifications' END
      || ':' || campfire_gid_param(room.type, room.id);
  END IF;

  RETURN CASE channel
    WHEN 'HeartbeatChannel' THEN ''
    WHEN 'ReadRoomsChannel' THEN 'user_' || p_user || '_reads'
    WHEN 'UnreadRoomsChannel' THEN 'user_' || p_user || '_unreads'
  END;
END $$;

-- Membership::Connectable, as PresenceChannel calls it. p_action is
-- present, absent or refresh.
CREATE FUNCTION campfire_presence(p_user bigint, p_room bigint, p_action text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  mb memberships;
  ts timestamp := utc_now();
  connected boolean;
BEGIN
  SELECT * INTO mb FROM memberships WHERE user_id = p_user AND room_id = p_room;
  IF mb.id IS NULL THEN RETURN; END IF;
  connected := mb.connected_at IS NOT NULL AND mb.connected_at >= ts - interval '60 seconds';
  IF p_action = 'present' THEN
    UPDATE memberships SET connections = CASE WHEN connected THEN mb.connections + 1 ELSE 1 END,
      connected_at = ts, unread_at = NULL WHERE id = mb.id;
    INSERT INTO cable_broadcasts (stream, payload)
    VALUES ('user_' || p_user || '_reads', json_build_object('room_id', p_room)::text);
  ELSIF p_action = 'absent' THEN
    UPDATE memberships SET connections = CASE WHEN connected THEN mb.connections - 1 ELSE 0 END, updated_at = ts
    WHERE id = mb.id;
    UPDATE memberships SET connected_at = NULL WHERE id = mb.id AND connections < 1;
  ELSIF p_action = 'refresh' THEN
    UPDATE memberships SET connections = CASE WHEN connected THEN mb.connections ELSE mb.connections + 1 END,
      connected_at = ts, updated_at = ts WHERE id = mb.id;
  END IF;
END $$;

-- Waits up to p_wait_ms for broadcasts on the given streams. p_subs is
-- [{"stream": ..., "since": id}, ...]; returns [{"i": index, "id": id, "payload": json}].
CREATE FUNCTION campfire_cable_poll(p_subs json, p_wait_ms int)
RETURNS json LANGUAGE plpgsql VOLATILE AS $$
DECLARE
  result json;
  deadline timestamptz := clock_timestamp() + make_interval(secs => p_wait_ms / 1000.0);
BEGIN
  LOOP
    SELECT json_agg(json_build_object('i', s.i - 1, 'id', b.id, 'payload', b.payload::json) ORDER BY b.id) INTO result
    FROM json_array_elements(p_subs) WITH ORDINALITY AS s(sub, i)
    JOIN cable_broadcasts b ON b.stream = s.sub->>'stream' AND b.id > (s.sub->>'since')::bigint;
    IF result IS NOT NULL OR clock_timestamp() >= deadline THEN
      RETURN coalesce(result, '[]'::json);
    END IF;
    PERFORM pg_sleep(0.1);
  END LOOP;
END $$;

CREATE FUNCTION campfire_cable_cursor() RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT coalesce(max(id), 0) FROM cable_broadcasts
$$;

-- Zlib.crc32, for Users::AvatarsHelper#avatar_background_color.
CREATE FUNCTION campfire_crc32(data text) RETURNS bigint LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  bytes bytea := convert_to(data, 'UTF8');
  crc bigint := 4294967295;
BEGIN
  FOR i IN 0 .. length(bytes) - 1 LOOP
    crc := crc # get_byte(bytes, i);
    FOR j IN 1 .. 8 LOOP
      crc := CASE WHEN crc & 1 = 1 THEN (crc >> 1) # 3988292384 ELSE crc >> 1 END;
    END LOOP;
  END LOOP;
  RETURN crc # 4294967295;
END $$;

-- User.from_avatar_token: find_signed!(token, purpose: :avatar)
CREATE FUNCTION campfire_user_from_avatar_token(token text) RETURNS bigint LANGUAGE plpgsql STABLE AS $$
DECLARE
  payload json;
BEGIN
  payload := campfire_verify(token, 'signed_id')::json;
  IF payload->'_rails'->>'pur' IS DISTINCT FROM 'user/avatar' THEN RETURN NULL; END IF;
  RETURN (SELECT id FROM users WHERE id = (payload->'_rails'->>'data')::bigint);
EXCEPTION WHEN others THEN
  RETURN NULL;
END $$;

-- The stored file (relative to storage/) for an account logo or user avatar
-- variant, when one has been uploaded; see lib/storage.gbln.
CREATE FUNCTION campfire_logo_file(small boolean) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT b.key || CASE WHEN small THEN '-small' ELSE '-large' END || '.png'
  FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id = a.blob_id
  WHERE a.record_type = 'Account' AND a.name = 'logo' ORDER BY a.id DESC LIMIT 1
$$;

CREATE FUNCTION campfire_avatar_file(user_id bigint) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT b.key || '-square.webp'
  FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id = a.blob_id
  WHERE a.record_type = 'User' AND a.name = 'avatar' AND a.record_id = user_id ORDER BY a.id DESC LIMIT 1
$$;

-- A message the user can reach (in one of their rooms), optionally only in
-- one room, with what the edit form needs: mentioned users by stored sgid,
-- each with a fresh sgid.
CREATE FUNCTION campfire_reachable_message(p_user bigint, p_message bigint, p_room bigint, p_for_edit boolean)
RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_build_object(
    'message', campfire_message_json(m),
    'room_type', r.type,
    'users', CASE WHEN p_for_edit THEN (
      SELECT json_object_agg(x.sgid, (campfire_user_json(u)::jsonb || jsonb_build_object('sgid', campfire_user_sgid(u.id)))::json)
      FROM (SELECT DISTINCT (regexp_matches(rt.body, 'sgid="([^"]+)"', 'g'))[1] AS sgid
            FROM action_text_rich_texts rt WHERE rt.record_type = 'Message' AND rt.record_id = m.id AND rt.name = 'body') x
      JOIN users u ON u.id = substring(campfire_unb64(split_part(x.sgid, '--', 1)) FROM 'gid://campfire/User/(\d+)')::bigint) END)
  FROM messages m
  JOIN rooms r ON r.id = m.room_id
  JOIN memberships mb ON mb.room_id = m.room_id AND mb.user_id = p_user
  WHERE m.id = p_message AND (p_room = 0 OR m.room_id = p_room)
$$;

-- Message#update! of the body, with its touches and the search index.
CREATE FUNCTION campfire_update_message(p_message bigint, p_body text, p_plain text)
RETURNS json LANGUAGE plpgsql AS $$
DECLARE
  ts timestamp := utc_now();
  m messages;
BEGIN
  INSERT INTO action_text_rich_texts (body, created_at, name, record_id, record_type, updated_at)
  VALUES (p_body, ts, 'body', p_message, 'Message', ts)
  ON CONFLICT (record_type, record_id, name) DO UPDATE SET body = excluded.body, updated_at = ts;
  UPDATE messages SET updated_at = ts WHERE id = p_message RETURNING * INTO m;
  UPDATE rooms SET updated_at = ts WHERE id = m.room_id;
  UPDATE message_search_index SET body = coalesce(p_plain, '') WHERE rowid = p_message;
  RETURN campfire_message_json(m);
END $$;

-- Message#destroy: boosts, rich text and the search index row go with it.
CREATE FUNCTION campfire_destroy_message(p_message bigint) RETURNS void LANGUAGE sql AS $$
  DELETE FROM boosts WHERE message_id = p_message;
  DELETE FROM action_text_rich_texts WHERE record_type = 'Message' AND record_id = p_message;
  DELETE FROM message_search_index WHERE rowid = p_message;
  DELETE FROM messages WHERE id = p_message;
$$;

-- Boost creation, touching the message and (through it) the room.
CREATE FUNCTION campfire_create_boost(p_user bigint, p_message bigint, p_content text)
RETURNS json LANGUAGE plpgsql AS $$
DECLARE
  ts timestamp := utc_now();
  b boosts;
BEGIN
  INSERT INTO boosts (message_id, booster_id, content, created_at, updated_at)
  VALUES (p_message, p_user, p_content, ts, ts) RETURNING * INTO b;
  UPDATE messages SET updated_at = ts WHERE id = p_message;
  UPDATE rooms SET updated_at = ts WHERE id = (SELECT room_id FROM messages WHERE id = p_message);
  RETURN json_build_object('id', b.id, 'content', b.content,
    'created_iso', campfire_iso(b.created_at), 'created_epoch', campfire_epoch(b.created_at),
    'booster', (SELECT campfire_user_json(u) FROM users u WHERE u.id = p_user));
END $$;

-- Mentioned users in a rich text body, by the sgid stored in it.
CREATE FUNCTION campfire_mentions(body text) RETURNS json LANGUAGE sql STABLE AS $$
  SELECT json_object_agg(x.sgid, campfire_user_json(u))
  FROM (SELECT DISTINCT (regexp_matches(body, 'sgid="([^"]+)"', 'g'))[1] AS sgid) x
  JOIN users u ON u.id = substring(campfire_unb64(split_part(x.sgid, '--', 1)) FROM 'gid://campfire/User/(\d+)')::bigint
$$;

-- ---------- Rooms ----------
-- memberships.grant_to: Membership.insert_all, which skips users who already
-- belong to the room. Users go in id order, as User.where(...) returns them.
CREATE FUNCTION campfire_grant(p_room bigint, p_users bigint[]) RETURNS void LANGUAGE sql AS $$
  INSERT INTO memberships (room_id, user_id, involvement, created_at, updated_at)
  SELECT p_room, u.id, CASE WHEN r.type = 'Rooms::Direct' THEN 'everything' ELSE 'mentions' END, utc_now(), utc_now()
  FROM users u, rooms r WHERE r.id = p_room AND u.id = ANY(p_users)
  ORDER BY u.id
  ON CONFLICT (room_id, user_id) DO NOTHING;
$$;

-- Rooms::Open#grant_access_to_all_users, after its type became Rooms::Open.
CREATE FUNCTION campfire_grant_all_active(p_room bigint) RETURNS void LANGUAGE sql AS $$
  SELECT campfire_grant(p_room, (SELECT coalesce(array_agg(id ORDER BY id), '{}') FROM users WHERE status = 0));
$$;

-- Room.create_for(attributes, users:), plus Rooms::Open's grant to everyone.
CREATE FUNCTION campfire_create_room(p_type text, p_name text, p_creator bigint, p_users bigint[])
RETURNS json LANGUAGE plpgsql AS $$
DECLARE
  r rooms;
BEGIN
  INSERT INTO rooms (type, name, creator_id, created_at, updated_at)
  VALUES (p_type, p_name, p_creator, utc_now(), utc_now()) RETURNING * INTO r;
  PERFORM campfire_grant(r.id, p_users);
  IF p_type = 'Rooms::Open' THEN PERFORM campfire_grant_all_active(r.id); END IF;
  RETURN campfire_room_json(r);
END $$;

-- Room#update!(name:) after becomes!(type); Rooms::Open grants everyone when
-- the type changed to it. Closed rooms then revise their memberships:
-- p_users (NULL for open rooms) are the grantees, everyone else is revoked.
CREATE FUNCTION campfire_update_room(p_room bigint, p_type text, p_name text, p_users bigint[])
RETURNS json LANGUAGE plpgsql AS $$
DECLARE
  was rooms;
  r rooms;
BEGIN
  SELECT * INTO was FROM rooms WHERE id = p_room;
  UPDATE rooms SET type = p_type, name = p_name,
    updated_at = CASE WHEN type IS DISTINCT FROM p_type OR name IS DISTINCT FROM p_name THEN utc_now() ELSE updated_at END
  WHERE id = p_room RETURNING * INTO r;
  IF p_type = 'Rooms::Open' AND was.type <> 'Rooms::Open' THEN PERFORM campfire_grant_all_active(p_room); END IF;
  IF p_users IS NOT NULL THEN
    PERFORM campfire_grant(p_room, p_users);
    DELETE FROM memberships WHERE room_id = p_room AND NOT (user_id = ANY(p_users));
  END IF;
  RETURN campfire_room_json(r);
END $$;

-- Rooms::Direct.find_or_create_for(users): the first direct room whose
-- members are exactly these users, else a new one.
CREATE FUNCTION campfire_find_or_create_direct(p_creator bigint, p_users bigint[])
RETURNS json LANGUAGE plpgsql AS $$
DECLARE
  wanted bigint[] := (SELECT coalesce(array_agg(id ORDER BY id), '{}') FROM users WHERE id = ANY(p_users));
  found bigint;
BEGIN
  SELECT r.id INTO found FROM rooms r
  WHERE r.type = 'Rooms::Direct'
    AND (SELECT array_agg(user_id ORDER BY user_id) FROM memberships WHERE room_id = r.id) = wanted
  ORDER BY r.id LIMIT 1;
  IF found IS NOT NULL THEN
    RETURN json_build_object('created', false, 'room', (SELECT campfire_room_json(r) FROM rooms r WHERE r.id = found));
  END IF;
  RETURN json_build_object('created', true, 'room', campfire_create_room('Rooms::Direct', NULL, p_creator, wanted));
END $$;

-- Room#destroy: memberships go with delete_all, messages one by one.
CREATE FUNCTION campfire_destroy_room(p_room bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  mid bigint;
BEGIN
  DELETE FROM memberships WHERE room_id = p_room;
  FOR mid IN SELECT id FROM messages WHERE room_id = p_room LOOP
    PERFORM campfire_destroy_message(mid);
  END LOOP;
  DELETE FROM rooms WHERE id = p_room;
END $$;

-- ---------- Users ----------
-- User#transfer_id: signed_id(purpose: :transfer, expires_in: 4.hours)
CREATE FUNCTION campfire_transfer_id(user_id bigint) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT campfire_sign('{"_rails":{"data":' || user_id || ',"exp":"'
    || to_char(utc_now() + interval '4 hours', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') || '","pur":"user/transfer"}}', 'signed_id')
$$;

-- User.find_by_transfer_id: find_signed(id, purpose: :transfer), unexpired.
CREATE FUNCTION campfire_user_from_transfer_id(token text) RETURNS bigint LANGUAGE plpgsql STABLE AS $$
DECLARE
  payload json;
BEGIN
  payload := campfire_verify(token, 'signed_id')::json;
  IF payload->'_rails'->>'pur' IS DISTINCT FROM 'user/transfer' THEN RETURN NULL; END IF;
  IF (payload->'_rails'->>'exp')::timestamp < utc_now() THEN RETURN NULL; END IF;
  RETURN (SELECT id FROM users WHERE id = (payload->'_rails'->>'data')::bigint);
EXCEPTION WHEN others THEN
  RETURN NULL;
END $$;

-- Ban#ip_address_is_public
CREATE FUNCTION campfire_public_ip(ip text) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  a inet;
BEGIN
  a := ip::inet;
  RETURN NOT (a << '127.0.0.0/8' OR a = '127.0.0.1' OR a = '::1' OR a << '10.0.0.0/8' OR a << '172.16.0.0/12'
    OR a << '192.168.0.0/16' OR a << 'fc00::/7' OR a << '169.254.0.0/16' OR a << 'fe80::/10');
EXCEPTION WHEN others THEN
  RETURN false;
END $$;

-- User#ban: a ban per session IP, sessions dropped, status banned, and
-- RemoveBannedContentJob's message removal. NULL when bans.create! would
-- fail validation (a private or invalid address), changing nothing.
CREATE FUNCTION campfire_ban_user(p_user bigint) RETURNS json LANGUAGE plpgsql AS $$
DECLARE
  removed json;
  mid bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM sessions WHERE user_id = p_user AND coalesce(ip_address, '') <> '' AND NOT campfire_public_ip(ip_address)) THEN
    RETURN NULL;
  END IF;
  INSERT INTO bans (user_id, ip_address, created_at, updated_at)
  SELECT p_user, ip, utc_now(), utc_now() FROM (
    SELECT DISTINCT ON (ip_address) ip_address AS ip, id FROM sessions WHERE user_id = p_user AND coalesce(ip_address, '') <> '' ORDER BY ip_address, id) s
  ORDER BY s.id;
  DELETE FROM sessions WHERE user_id = p_user;
  UPDATE users SET status = 2, updated_at = utc_now() WHERE id = p_user;
  SELECT coalesce(json_agg(json_build_object('id', m.client_message_id,
    'stream', campfire_gid_param(r.type, r.id) || ':messages') ORDER BY m.id), '[]')
  INTO removed FROM messages m JOIN rooms r ON r.id = m.room_id WHERE m.creator_id = p_user;
  FOR mid IN SELECT id FROM messages WHERE creator_id = p_user LOOP
    PERFORM campfire_destroy_message(mid);
  END LOOP;
  RETURN json_build_object('messages', removed);
END $$;

-- ---------- Accounts ----------
-- User#deactivate
CREATE FUNCTION campfire_deactivate_user(p_user bigint) RETURNS void LANGUAGE sql AS $$
  DELETE FROM memberships WHERE user_id = p_user AND room_id IN (SELECT id FROM rooms WHERE type <> 'Rooms::Direct');
  DELETE FROM push_subscriptions WHERE user_id = p_user;
  DELETE FROM searches WHERE user_id = p_user;
  DELETE FROM sessions WHERE user_id = p_user;
  UPDATE users SET status = 1, updated_at = utc_now(),
    email_address = replace(email_address, '@', '-deactivated-' || gen_random_uuid() || '@')
  WHERE id = p_user;
$$;

-- User#grant_membership_to_open_rooms (after_create_commit)
CREATE FUNCTION campfire_grant_open_rooms(p_user bigint) RETURNS void LANGUAGE sql AS $$
  INSERT INTO memberships (room_id, user_id, created_at, updated_at)
  SELECT r.id, p_user, utc_now(), utc_now() FROM rooms r WHERE r.type = 'Rooms::Open' ORDER BY r.id
  ON CONFLICT (room_id, user_id) DO NOTHING;
$$;

-- User.create_bot!
CREATE FUNCTION campfire_create_bot(p_name text, p_token text, p_webhook text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  uid bigint;
BEGIN
  INSERT INTO users (name, role, status, bot_token, created_at, updated_at)
  VALUES (p_name, 2, 0, p_token, utc_now(), utc_now()) RETURNING id INTO uid;
  IF p_webhook IS NOT NULL THEN
    INSERT INTO webhooks (user_id, url, created_at, updated_at) VALUES (uid, p_webhook, utc_now(), utc_now());
  END IF;
  PERFORM campfire_grant_open_rooms(uid);
  RETURN uid;
END $$;

-- User#update_webhook_url!: a present URL updates or creates the webhook,
-- a blank one removes it.
CREATE FUNCTION campfire_update_webhook(p_user bigint, p_url text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(btrim(p_url), '') <> '' THEN
    UPDATE webhooks SET url = p_url, updated_at = CASE WHEN url IS DISTINCT FROM p_url THEN utc_now() ELSE updated_at END WHERE user_id = p_user;
    IF NOT FOUND THEN
      INSERT INTO webhooks (user_id, url, created_at, updated_at) VALUES (p_user, p_url, utc_now(), utc_now());
    END IF;
  ELSE
    DELETE FROM webhooks WHERE user_id = p_user;
  END IF;
END $$;

-- ---------- Onboarding ----------
-- User.create! with has_secure_password, then grant_membership_to_open_rooms.
-- NULL when the email address is taken (ActiveRecord::RecordNotUnique).
CREATE FUNCTION campfire_create_user(p_name text, p_email text, p_password text, p_role int DEFAULT 0)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  uid bigint;
BEGIN
  INSERT INTO users (name, email_address, password_digest, role, status, created_at, updated_at)
  VALUES (p_name, p_email, CASE WHEN coalesce(p_password, '') <> '' THEN crypt(p_password, gen_salt('bf', 12)) END,
    p_role, 0, utc_now(), utc_now())
  RETURNING id INTO uid;
  PERFORM campfire_grant_open_rooms(uid);
  RETURN uid;
EXCEPTION WHEN unique_violation THEN
  RETURN NULL;
END $$;

-- FirstRun.create!: the account, its administrator and the first room.
CREATE FUNCTION campfire_first_run(p_join_code text, p_name text, p_email text, p_password text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  uid bigint;
BEGIN
  INSERT INTO accounts (name, join_code, created_at, updated_at) VALUES ('Campfire', p_join_code, utc_now(), utc_now());
  uid := campfire_create_user(p_name, p_email, p_password, 1);
  IF uid IS NULL THEN RAISE unique_violation; END IF;
  PERFORM campfire_create_room('Rooms::Open', 'All Talk', uid, ARRAY[uid]);
  RETURN uid;
EXCEPTION WHEN unique_violation THEN
  RETURN NULL;
END $$;
