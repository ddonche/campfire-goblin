# Builds the benchmark seed inside a Campfire checkout:
#
#   cd once-campfire && bin/rails db:prepare db:fixtures:load
#   bin/rails runner path/to/campfire-goblin/bench/seed.rb OUT_DIR
#
# Campfire's bench/ drivers expect a seed directory with db/, storage/ and
# labels.json. The upstream repository does not ship the seed itself, so this
# script grows the test fixtures into one: 120 "busy" messages in the
# watercooler room (some mentioning coffee), with boosts, then writes labels.
require "fileutils"
require "json"

out = File.expand_path(ARGV.fetch(0, "tmp/bench-seed"))
users = User.where(role: [ :member, :administrator ]).order(:id).to_a
room = Room.find(ActiveRecord::FixtureSet.identify(:watercooler))
phrases = [
  "Anyone want coffee?", "Shipping the new build now.", "Lunch in ten minutes.",
  "The coffee machine is broken again", "Reviewing the pull request.", "Great work on the launch!",
  "Can someone look at the failing test?", "Fresh coffee in the kitchen", "Meeting moved to 3pm.",
  "Who has the keys to the office?"
]
start = Time.utc(2026, 1, 5, 9, 0, 0)
labels = {}
Current.set(user: users.first) do
  # A few messages with the rich text Campfire produces: mentions, links,
  # formatting, an emoji-only message and a /play sound.
  kevin = User.find_by!(email_address: "kevin@37signals.com")
  mention = %(<action-text-attachment sgid="#{kevin.attachable_sgid}" content-type="application/vnd.campfire.mention"></action-text-attachment>)
  rich = [
    %(<p>Hey #{mention}, the coffee notes are at https://example.com/coffee?roast=dark.</p>),
    %(<p><strong>Bold</strong>, <em>italic</em> &amp; <a href="https://basecamp.com">a link</a></p><ul><li>one</li><li>two</li></ul>),
    %(<pre data-language="ruby">puts "hi" &lt;3</pre><p>Email me at david@example.com <script>alert(1)</script></p>),
    "🔥🔥",
    "/play trombone"
  ]
  rich.each_with_index do |body, i|
    room.messages.create!(creator: users[i % users.size], body: body, client_message_id: "rich-#{i}",
      created_at: start - (rich.size - i).minutes, updated_at: start - (rich.size - i).minutes)
  end

  1.upto(120) do |i|
    creator = users[i % users.size]
    body = "#{phrases[i % phrases.size]} (#{i})"
    message = room.messages.create!(creator: creator, body: body, client_message_id: "busy-#{i}",
      created_at: start + i.minutes, updated_at: start + i.minutes)
    if i % 7 == 0
      message.boosts.create!(booster: users[(i + 1) % users.size], content: "👍", created_at: start + i.minutes + 30)
    end
    labels["messages.busy_%03d" % i] = message.id
  end
end
labels["rooms.watercooler"] = room.id
labels["emails.david"] = "david@37signals.com"
labels["passwords.all"] = "secret123456"

FileUtils.mkdir_p(out)
FileUtils.rm_rf(File.join(out, "db"))
ActiveRecord::Base.connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
FileUtils.cp_r(Rails.root.join("storage/db"), File.join(out, "db"))
FileUtils.cp_r(Rails.root.join("storage/files"), File.join(out, "storage")) if Rails.root.join("storage/files").exist?
FileUtils.mkdir_p(File.join(out, "storage"))
File.write(File.join(out, "labels.json"), JSON.pretty_generate(labels) + "\n")
puts "seed written to #{out}"
