require 'resque/failure/redis'
require 'resque/failure/multiple_with_retry_suppression'

Dir.glob Rails.root.join('app', 'jobs', 'data_migrations', "*.rb") do |f|
  require_dependency Rails.root.join('app', 'jobs', 'data_migrations', f)
end

redis_url = nil
puts "Configuring Redis.."

if ENV["REDIS_HOST"].present?
  REDIS_OPTS = opts = {
    :host =>     ENV['REDIS_HOST'],
    :port =>     ENV['REDIS_PORT'],
    :password => ENV['REDIS_PASSWORD']
  }
  url = "redis://:#{opts[:password]}@#{opts[:host]}}:#{opts[:port]}"
  ENV["RAILS_RESQUE_REDIS"] = url
  # Seperate Redis connections for the resque and general purpose redis
  # connection. This is because all resque pub/sub keys are automatically
  #prefixed by the string "resque:".
  $redis = Redis.new REDIS_OPTS
  Resque.redis = Redis.new REDIS_OPTS
  Resque.schedule = YAML.load_file Rails.root.join 'config', 'schedule.yml'
  puts "Redis Configured."
else
  REDIS_OPTS = {host: "localhost", port: 6379}
  REDIS_OPTS[:db] = 1 if Rails.env.development?
  REDIS_OPTS[:db] = 2 if Rails.env.test?
  $redis = Redis.new REDIS_OPTS
  puts "Redis Configured for Development."
end

Resque.inline = Rails.env.test? or Rails.env.development?
# Resque status
Resque::Plugins::Status::Hash.expire_in = (24 * 60 * 60) # 24hrs in seconds
# Resque failure retries
Resque::Failure::MultipleWithRetrySuppression.classes = [Resque::Failure::Redis]
Resque::Failure.backend = Resque::Failure::MultipleWithRetrySuppression

Resque.after_fork do |job|
  # Reconnecting the non-resque redis client
  $redis.client.reconnect
end