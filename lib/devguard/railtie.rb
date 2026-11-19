# frozen_string_literal: true

if defined?(Rails::Railtie)
  module DevGuard
    class Railtie < ::Rails::Railtie
      initializer "devguard.insert_middleware" do |app|
        app.middleware.use DevGuard::Middleware
      end
    end
  end
end
