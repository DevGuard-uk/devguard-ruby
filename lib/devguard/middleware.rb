# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "thread"
require "timeout"

module DevGuard
  class Middleware
    LOCKED_STATUSES = %w[locked autolocked payment_past_due].freeze

    def initialize(app, options = {})
      @app = app
      @options = options || {}
      @cache_mutex = Mutex.new
      @cached_status = nil
      @cached_at = 0.0
    end

    def call(env)
      path = env["PATH_INFO"] || ""

      # 1. Bypass paths check
      if bypassed_path?(path)
        return @app.call(env)
      end

      # 2. Domain verification
      raw_host = env["HTTP_HOST"] || env["SERVER_NAME"] || ""
      unless domain_allowed?(raw_host)
        return [
          403,
          {
            "Content-Type" => "text/plain",
            "X-DevGuard-Status" => "domain_unauthorized"
          },
          ["Domain unauthorized by DevGuard\n"]
        ]
      end

      # 3. Status check against DevGuard API
      status = fetch_project_status
      if status_locked?(status)
        return lock_response
      end

      # 4. Active passthrough
      @app.call(env)
    rescue => e
      handle_failure(e, env)
    end

    def clear_cache!
      @cache_mutex.synchronize do
        @cached_status = nil
        @cached_at = 0.0
      end
    end

    private

    def config
      DevGuard.configuration
    end

    def project_id
      @options[:project_id] || config.project_id
    end

    def api_key
      @options[:sdk_key] || @options[:api_key] || config.sdk_key || config.api_key
    end

    def api_url
      @options[:api_url] || config.api_url || Configuration::DEFAULT_API_URL
    end

    def fail_safe_open?
      val = (@options.key?(:fail_safe) ? @options[:fail_safe] : config.fail_safe).to_s.strip.downcase
      val == "open" || val == "true"
    end

    def timeout_seconds
      (@options[:timeout_seconds] || config.timeout_seconds || Configuration::DEFAULT_TIMEOUT_SECONDS).to_f
    end

    def cache_ttl_seconds
      (@options[:cache_ttl_seconds] || config.cache_ttl_seconds || Configuration::DEFAULT_CACHE_TTL_SECONDS).to_f
    end

    def allowed_domains
      domains = @options[:allowed_domains] || config.allowed_domains || []
      Array(domains)
    end

    def bypass_paths
      paths = @options[:bypass_paths] || config.bypass_paths || Configuration::DEFAULT_BYPASS_PATHS
      Array(paths)
    end

    def lock_html_content
      @options[:lock_html] || config.lock_html || default_lock_html(project_id)
    end

    def bypassed_path?(path)
      bypass_paths.any? { |prefix| path.start_with?(prefix) }
    end

    def normalize_host(raw_host)
      return "" if raw_host.nil?

      host = raw_host.to_s.strip.downcase
      return "" if host.empty?

      # Reject invalid / header injection characters
      return "" if host =~ /[\r\n\0\s\\?#@\/]/

      # IPv6 bracket notation [::1]:port
      if host.start_with?("[")
        end_bracket = host.index("]")
        return host[1...end_bracket] if end_bracket
      end

      # Strip port if present
      host = host.split(":").first || ""

      # Strip trailing dot
      host = host.chop if host.end_with?(".")

      host
    end

    def domain_allowed?(raw_host)
      domains = allowed_domains
      return true if domains.empty?

      normalized = normalize_host(raw_host)
      return false if normalized.empty?

      domains.any? do |raw_pattern|
        next false if raw_pattern.nil?

        pat = raw_pattern.to_s.strip.downcase
        next false if pat.empty?

        if pat == "*"
          true
        elsif pat.start_with?("*.")
          base = normalize_host(pat[2..-1])
          next false if base.empty?

          normalized == base || normalized.end_with?("." + base)
        else
          normalized_pat = normalize_host(pat)
          !normalized_pat.empty? && normalized == normalized_pat
        end
      end
    end

    def fetch_project_status
      # Check in-memory cache first
      @cache_mutex.synchronize do
        now = Time.now.to_f
        if @cached_status && (now - @cached_at < cache_ttl_seconds)
          return @cached_status
        end
      end

      pid = project_id
      return "active" if pid.nil? || pid.to_s.strip.empty?

      status = query_api(pid)

      @cache_mutex.synchronize do
        @cached_status = status
        @cached_at = Time.now.to_f
      end

      status
    end

    def query_api(pid)
      endpoint = "#{api_url.chomp('/')}/api/v1/projects/#{pid}/status"
      uri = URI.parse(endpoint)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = timeout_seconds
      http.read_timeout = timeout_seconds

      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = "DevGuard-Ruby/#{DevGuard::VERSION}"
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}" if api_key && !api_key.to_s.empty?

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        parsed = JSON.parse(response.body) rescue {}
        parsed["status"] ? parsed["status"].to_s.downcase : "active"
      else
        raise "DevGuard API returned HTTP #{response.code}"
      end
    end

    def status_locked?(status)
      LOCKED_STATUSES.include?(status.to_s.downcase)
    end

    def lock_response
      [
        503,
        {
          "Content-Type" => "text/html; charset=utf-8",
          "Retry-After" => "3600",
          "X-Robots-Tag" => "noindex, nofollow, noarchive",
          "X-DevGuard-Status" => "locked"
        },
        [lock_html_content]
      ]
    end

    def handle_failure(error, env)
      if fail_safe_open?
        log_warning("DevGuard check failed: #{error.message}. Fail-safe open: passing through.")
        @app.call(env)
      else
        log_error("DevGuard check failed: #{error.message}. Fail-safe closed: returning 503.")
        lock_response
      end
    end

    def log_warning(msg)
      if defined?(Rails.logger) && Rails.logger
        Rails.logger.warn("[DevGuard] #{msg}")
      else
        warn("[DevGuard] #{msg}")
      end
    end

    def log_error(msg)
      if defined?(Rails.logger) && Rails.logger
        Rails.logger.error("[DevGuard] #{msg}")
      else
        warn("[DevGuard ERROR] #{msg}")
      end
    end

    def default_lock_html(pid)
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <meta name="robots" content="noindex, nofollow, noarchive" />
          <title>Service Unavailable - DevGuard</title>
          <style>
            body {
              background-color: #0b0f19;
              color: #f3f4f6;
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
              display: flex;
              align-items: center;
              justify-content: center;
              min-height: 100vh;
              margin: 0;
              padding: 1.5rem;
              box-sizing: border-box;
            }
            .container {
              background: #111827;
              border: 1px solid #1f2937;
              border-radius: 12px;
              max-width: 520px;
              padding: 2.5rem;
              text-align: center;
              box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
            }
            h1 { font-size: 1.5rem; margin-bottom: 1rem; color: #f87171; }
            p { color: #9ca3af; line-height: 1.6; margin-bottom: 1.5rem; }
            .meta { font-size: 0.85rem; color: #6b7280; border-top: 1px solid #1f2937; padding-top: 1rem; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Service Temporarily Unavailable</h1>
            <p>This application is temporarily suspended pending administrative milestone verification.</p>
            <div class="meta">DevGuard Protection Active &bull; Project: #{pid || 'Protected'}</div>
          </div>
        </body>
        </html>
      HTML
    end
  end
end
