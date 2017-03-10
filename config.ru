require 'fileutils'
require 'logger'
require 'sequel'
require 'pact_broker'

DB_URL = ENV.fetch('DATABASE_URL')
AUTH_USERNAME = ENV.fetch('AUTH_USERNAME')
AUTH_PASSWORD = ENV.fetch('AUTH_PASSWORD')

class NonGetBasicAuth < Rack::Auth::Basic
  def call(env)
    if ['GET', 'HEAD'].include?(env['REQUEST_METHOD'])
      return @app.call(env)
    end
    super
  end
end

use NonGetBasicAuth, "Restricted write access" do |username, password|
  username == AUTH_USERNAME && password == AUTH_PASSWORD
end

# Version handler that supports branch names as well as numeric versions.
# Branch names sort after any numeric versions so that latest will always
# return the latest released version
class CustomVersionParser
  def self.call(string_version)
    case string_version
    when "master", /\Abranch-/
      Version.new(string_version)
    else
      Version.new(::Versionomy.parse(string_version))
    end
  rescue ::Versionomy::Errors::ParseError => e
    nil
  end

  Version = Struct.new(:version) do
    def branch?
      version.is_a?(String)
    end

    def <=>(other)
      return version <=> other.version if branch? && other.branch?
      return -1 if branch?
      return 1 if other.branch?
      version <=> other.version
    end
  end
end

app = PactBroker::App.new do | config |
  # change these from their default values if desired
  # config.log_dir = "./log"
  # config.auto_migrate_db = true
  # config.use_hal_browser = true
  config.logger = Logger.new($stdout)

  # Have a look at the Sequel documentation to make decisions about things like connection pooling
  # and connection validation.
  connection = Sequel.connect(DB_URL, :encoding => 'utf8', :logger => config.logger)
  # This is a fix for a postgres losing connection error: https://github.com/bethesque/pact_broker/issues/39
  connection.extension(:connection_validator)
  connection.pool.connection_validation_timeout = -1
  config.database_connection = connection
  config.version_parser = CustomVersionParser
end

run app
