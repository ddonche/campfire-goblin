# Signs in the way Campfire's bench/http_client.rb does and saves the four
# benchmarked pages (plus a few others) so two implementations can be diffed.
#
#   ruby bench/fetch_pages.rb http://127.0.0.1:3001 SEED_DIR OUT_DIR
require "json"
require "fileutils"
require_relative "http_client"

base, seed, out = ARGV
labels = JSON.parse(File.read(File.join(seed, "labels.json")))
client = BenchmarkHTTPClient.new(base)
cookie = client.login(labels)
FileUtils.mkdir_p(out)
room = labels.fetch("rooms.watercooler")
pages = {
  "room" => "/rooms/#{room}",
  "messages" => "/rooms/#{room}/messages?before=#{labels.fetch('messages.busy_060')}",
  "sidebar" => "/users/me/sidebar",
  "search" => "/searches?q=coffee"
}
pages.merge!(JSON.parse(ARGV[3])) if ARGV[3]
uri = URI(base)
Net::HTTP.start(uri.host, uri.port) do |http|
  pages.each do |name, path|
    response = http.get(path, "Cookie" => cookie, "Accept-Encoding" => "identity")
    File.write(File.join(out, "#{name}.html"), response.body)
    puts "#{name}: #{response.code} #{response.body.bytesize} bytes #{path}"
  end
end
