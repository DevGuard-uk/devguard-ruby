# frozen_string_literal: true

require_relative "lib/devguard/version"

Gem::Specification.new do |spec|
  spec.name          = "devguard-ruby"
  spec.version       = DevGuard::VERSION
  spec.authors       = ["DevGuard"]
  spec.email         = ["support@devguard.uk"]
  spec.summary       = "DevGuard Rack Middleware and Rails Railtie for web milestone licensing and anti-theft protection"
  spec.description   = "Zero-dependency Rack middleware providing fail-safe domain locking, automated milestone invoice checks, and SEO-safe 503 lockout pages for Ruby on Rails and Sinatra applications."
  spec.homepage      = "https://devguard.uk"
  spec.license       = "MIT"
  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.5.0"
end
