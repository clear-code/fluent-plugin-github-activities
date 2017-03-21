require "fluent/plugin/github-activities"

crawler = Fluent::Plugin::GithubActivities::Crawler.new
crawler.on_emit = lambda do |tag, record|
  puts "EMIT: #{tag}"
end
crawler.reserve_user_events("piroor")
crawler.request_queue
crawler.process_request
crawler.request_queue.size
(crawler.request_queue.size - 1).times do crawler.request_queue.shift end
crawler.process_request
crawler.request_queue
