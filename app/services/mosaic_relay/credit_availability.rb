# frozen_string_literal: true

require "securerandom"
require "time"
require "redis"

module MosaicRelay
  class CreditAvailability
    CACHE_PREFIX = "relay_chat_unavailable_until".freeze
    LOCK_PREFIX = "relay_chat_unavailable_lock".freeze
    LOCK_TTL_SECONDS = 5

    class CacheUnavailable < StandardError; end

    def self.available? = new.available?

    def self.mark_unavailable!(resets_at:) = new.mark_unavailable!(resets_at:)

    def self.clear_unavailability! = new.clear_unavailability!

    def self.stream_name
      "relay_chat:#{MosaicRelay.configuration.chat_tenant_key}"
    end

    def initialize(redis: nil, broadcaster: nil)
      @redis = redis || MosaicRelay.configuration.redis || default_redis
      @broadcaster = broadcaster || MosaicRelay.configuration.broadcaster || ActionCable.server
    end

    def available?
      value = redis.get(cache_key)
      return true if value.blank?

      reset_at = Time.iso8601(value)
      return false if reset_at.future?

      redis.del(cache_key)
      true
    rescue Redis::BaseError, ArgumentError, TypeError => e
      raise CacheUnavailable, e.message
    end

    def mark_unavailable!(resets_at:)
      reset_at = Time.iso8601(resets_at.to_s)
      return false unless reset_at.future?

      changed = with_lock do
        existing_value = redis.get(cache_key).presence
        existing_reset_at = Time.iso8601(existing_value) if existing_value
        next false if existing_reset_at && existing_reset_at >= reset_at

        redis.set(cache_key, reset_at.iso8601, ex: [ (reset_at - Time.current).ceil, 1 ].max)
        true
      end

      broadcaster.broadcast(self.class.stream_name, { type: "chat_unavailable" }) if changed
      changed
    rescue Redis::BaseError, ArgumentError, TypeError => e
      raise CacheUnavailable, e.message
    end

    def clear_unavailability!
      redis.del(cache_key)
      true
    rescue Redis::BaseError => e
      raise CacheUnavailable, e.message
    end

    private

    attr_reader :redis, :broadcaster

    def default_redis
      return $redis if defined?($redis) && $redis

      raise CacheUnavailable, "Redis has not been configured for MosaicRelay."
    end

    def cache_key
      "#{CACHE_PREFIX}:#{MosaicRelay.configuration.chat_tenant_key}"
    end

    def lock_key
      "#{LOCK_PREFIX}:#{MosaicRelay.configuration.chat_tenant_key}"
    end

    def with_lock
      token = SecureRandom.hex(12)
      acquired = false
      20.times do
        acquired = redis.set(lock_key, token, nx: true, ex: LOCK_TTL_SECONDS)
        break if acquired

        sleep 0.025
      end
      raise CacheUnavailable, "Unable to acquire the Relay credit availability lock." unless acquired

      yield
    ensure
      release_lock(token) if acquired
    end

    def release_lock(token)
      redis.eval(<<~LUA, keys: [ lock_key ], argv: [ token ])
        if redis.call("GET", KEYS[1]) == ARGV[1] then
          return redis.call("DEL", KEYS[1])
        end
        return 0
      LUA
    end
  end
end
