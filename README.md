# DevGuard Ruby Guard (`devguard-ruby`)

Rack middleware and Ruby on Rails Railtie for **DevGuard** anti-theft protection, domain allowlisting, invoice milestone autolock enforcement, and SEO-safe HTTP 503 lockouts.

Supports **Ruby on Rails**, **Sinatra**, and any standard **Rack** application.

---

## Features

- **Zero External Dependencies**: Uses only standard library modules (`net/http`, `uri`, `json`, `thread`, `timeout`).
- **Fail-Safe Open Policy**: Network timeouts, DNS anomalies, or API downtime will not interrupt client traffic.
- **Domain Authorization**: Enforces authorized hostnames with full support for wildcard subdomains (`*.example.com`).
- **Milestone Autolock**: Automatically verifies project licensing status with local thread-safe TTL caching.
- **SEO-Safe HTTP 503**: Returns status 503 with `Retry-After: 3600` and `X-Robots-Tag: noindex, nofollow, noarchive` during administrative locks.

---

## Installation

Add to your Gemfile:

```ruby
gem "devguard-ruby"
```

And execute:

```bash
bundle install
```

---

## Configuration & Usage

### 1. Ruby on Rails

Create an initializer at `config/initializers/devguard.rb`:

```ruby
DevGuard.configure do |config|
  config.project_id        = ENV["DEVGUARD_PROJECT_ID"]
  # Prefer project SDK key (Portal → Project SDK key). Falls back to DEVGUARD_API_KEY.
  config.sdk_key           = ENV["DEVGUARD_SDK_KEY"]
  config.allowed_domains   = ["example.com", "*.example.com"]
  config.fail_safe         = :open # :open or :closed
  config.timeout_seconds   = 2.5
  config.cache_ttl_seconds = 60
end
```

The Railtie automatically inserts `DevGuard::Middleware` into the Rails middleware stack.

### 2. Sinatra

```ruby
require "sinatra"
require "devguard"

DevGuard.configure do |config|
  config.project_id      = "proj_your_project_id"
  config.allowed_domains = ["mysite.com"]
end

use DevGuard::Middleware

get "/" do
  "Hello from Sinatra"
end
```

### 3. Plain Rack (`config.ru`)

```ruby
require "devguard"

DevGuard.configure do |config|
  config.project_id      = "proj_your_project_id"
  config.allowed_domains = ["mysite.com"]
end

use DevGuard::Middleware

run ->(env) { [200, { "Content-Type" => "text/plain" }, ["OK"]] }
```
