require 'cequel'
require 'redis'

require 'octocore/models/enterprise'
require 'octocore/models/enterprise/api_hit'
require 'octocore/models/enterprise/api_event'
require 'octocore/models/enterprise/app_init'
require 'octocore/models/enterprise/app_login'
require 'octocore/models/enterprise/app_logout'
require 'octocore/models/enterprise/authorization'
require 'octocore/models/enterprise/category'
require 'octocore/models/enterprise/category_baseline'
require 'octocore/models/enterprise/category_hit'
require 'octocore/models/enterprise/category_trend'
require 'octocore/models/enterprise/gcm'
require 'octocore/models/enterprise/page'
require 'octocore/models/enterprise/product'
require 'octocore/models/enterprise/product_baseline'
require 'octocore/models/enterprise/product_hit'
require 'octocore/models/enterprise/product_trend'
require 'octocore/models/enterprise/push_key'
require 'octocore/models/enterprise/tag'
require 'octocore/models/enterprise/tag_hit'
require 'octocore/models/enterprise/tag_baseline'
require 'octocore/models/enterprise/tag_trend'
require 'octocore/models/enterprise/template'

require 'octocore/models/user'
require 'octocore/models/user/push_token'
require 'octocore/models/user/user_location_history'
require 'octocore/models/user/user_phone_details'

require 'octocore/utils'


module Cequel
  module Record

    # Updates caching config
    # @param [String] host The host to connect to
    # @param [Fixnum] port The port to connect to
    def self.update_cache_config(host, port)
      @redis = Redis.new(host: host,
                         port: port,
                         driver: :hiredis)
    end

    # Getter for redis object
    # @return [Redis] redis cache instance
    def self.redis
      @redis
    end

    # Override Cequel::Record here
    module ClassMethods

      # Recreates this object from other object
      def recreate_from(obj)
        keys = self.key_column_names
        args = {}
        if obj.respond_to?:enterprise_id and obj.respond_to?:uid
          args[keys.delete(:enterprise_id)] = obj.enterprise_id
          if keys.length == 1
            args[keys.first] = obj.uid
            self.get_cached(args)
          else
            puts keys.to_a.to_s
            raise NotImplementedError, 'See octocore/models.rb'
          end
        end
      end

      # If a record exists, will find it and update it's value with the
      #   provided options. Else, will just create the record.
      def findOrCreateOrUpdate(args, options = {})
        cache_key = gen_cache_key(args)
        res = get_cached(args)
        if res
          dirty = false
          options.keys.each do |k|
            if res.respond_to?(k)
              unless res.public_send(k.to_sym) == options[k]
                dirty = true
              end
            end
          end
          if dirty
            args.merge!(options)
            res = self.new(args).save!
            Cequel::Record.redis.setex(cache_key, get_ttl, Octo::Utils.serialize(res))
          end
        else
          args.merge!(options)
          res = self.new(args).save!
          Cequel::Record.redis.setex(cache_key, get_ttl, Octo::Utils.serialize(res))
        end
        res
      end

      # Finds the record/recordset satisfying a `where` condition
      #   or create a new record from the params passed
      # @param [Hash] args The args used to build `where` condition
      # @param [Hash] options The options used to construct record
      def findOrCreate(args, options = {})
        # attempt to find the record
        res = get_cached(args)

        # on failure, do
        unless res
          args.merge!(options)
          res = self.new(args).save!

          # Update cache
          cache_key = gen_cache_key(args)
          Cequel::Record.redis.setex(cache_key, get_ttl, Octo::Utils.serialize(res))
        end
        res
      end

      # Perform a cache backed get
      # @param [Hash] args The arguments hash for the record
      #   to be found
      # @return [Cequel::Record::RecordSet] The record matching
      def get_cached(args)
        cache_key = gen_cache_key(args)
        begin
          cached_val = Cequel::Record.redis.get(cache_key)
        rescue Exception => e
          puts e
          cached_val = nil
        end

        unless cached_val
          res = where(args)
          result_count = res.count
          if result_count == 0
            return nil
          elsif result_count == 1
            cached_val = Octo::Utils.serialize(res.first)
            Cequel::Record.redis.setex(cache_key, get_ttl, cached_val)
          elsif result_count > 1
            cached_val = Octo::Utils.serialize(res)
            Cequel::Record.redis.setex(cache_key, get_ttl, cached_val)
          end
        end
        Octo::Utils.deserialize(cached_val)
      end

      private

      # Generate cache key
      # @param [Hash] args The arguments for fetching hash
      # @return [String] Cache key generated
      def gen_cache_key(args)
        args = args.flatten
        args.unshift(self.name.to_s)
        args.join('::')
      end

      def get_ttl
        # default ttl of 1 hour
        ttl = 60
        if self.constants.include?(:TTL)
          ttl = self.const_get(:TTL)
        end

        # convert ttl into seconds
        ttl *= 60
      end

    end
  end
end