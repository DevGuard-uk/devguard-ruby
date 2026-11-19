# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "thread"
require "timeout"

require_relative "devguard/version"
require_relative "devguard/configuration"
require_relative "devguard/middleware"

if defined?(Rails::Railtie)
  require_relative "devguard/railtie"
end

module DevGuard
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
