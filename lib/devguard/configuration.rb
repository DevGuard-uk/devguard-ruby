# frozen_string_literal: true

module DevGuard
  class Configuration
    DEFAULT_API_URL = "https://api.devguard.uk"
    DEFAULT_TIMEOUT_SECONDS = 2.5
    DEFAULT_CACHE_TTL_SECONDS = 60
    DEFAULT_BYPASS_PATHS = [
      "/assets",
      "/favicon.ico",
      "/robots.txt",
      "/_devguard/health"
    ].freeze

    attr_accessor :project_id,
                  :api_key,
                  :api_url,
                  :fail_safe,
                  :timeout_seconds,
                  :cache_ttl_seconds,
                  :allowed_domains,
                  :bypass_paths,
                  :lock_html

    def initialize
      @project_id = nil
      @api_key = nil
      @api_url = DEFAULT_API_URL
      @fail_safe = :open
      @timeout_seconds = DEFAULT_TIMEOUT_SECONDS
      @cache_ttl_seconds = DEFAULT_CACHE_TTL_SECONDS
      @allowed_domains = []
      @bypass_paths = DEFAULT_BYPASS_PATHS.dup
      @lock_html = nil
    end

    def fail_safe_open?
      val = @fail_safe.to_s.strip.downcase
      val == "open" || val == "true"
    end
  end
end
