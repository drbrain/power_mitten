##
# Logs in to keystone every other second and records statistics on HTTP
# connect, Keystone login time and total request time.
#
# Uses the keystone_username, keystone_password and keystone_tenant values
# from the configuration file.

class PowerMitten::KeystonePing < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  ##
  # Creates a new KeystonePing service.  The service will use the following
  # +options+:
  #
  # keystone_url::
  #   The URL for keystone from your .novarc file.
  # keystone_username::
  #   Your username
  # keystone_password::
  #   Your password
  # keystone_tenant::
  #   The tenant for the username and password

  def initialize options
    require 'json'
    require 'net/http'
    require 'uri'

    super

    url = URI options['keystone_url']
    url += './tokens'

    @keystone_login = keystone_login_request_body options
    @keystone_path  = url.path
    @http           = http url

    @connect_time = nil
    @login_time   = nil
    @total_time   = nil
  end

  def http keystone_url # :nodoc:
    http = Net::HTTP.new keystone_url.host, keystone_url.port
    http.use_ssl = keystone_url.scheme.downcase == 'https'
    http
  end

  def keystone_login_request_body options # :nodoc:
    keystone_login = {
      'auth' => {
        'passwordCredentials' => {
          'username' => options['keystone_username'],
          'password' => options['keystone_password'],
        },
        'tenantName' => options['keystone_tenant'],
      }
    }

    JSON.dump keystone_login
  end

  ##
  # Logs in to keystone and records statistics for HTTP connect time, login
  # time and total request time.

  def login
    request = Net::HTTP::Post.new @keystone_path
    request.body = @keystone_login

    start_time     = Time.now
    connected_time = nil
    complete_time  = nil

    @http.start do
      connected_time = Time.now

      response = @http.request request

      complete_time = Time.now

      notice "Keystone login: #{response.code}"
    end

    @connect_time.add_value connected_time - start_time
    @login_time.add_value   complete_time  - connected_time
    @total_time.add_value   complete_time  - start_time
  end

  def run # :nodoc:
    super do
      @connect_time = get_statistic 'Keystone Connect'
      @login_time   = get_statistic 'Keystone Login'
      @total_time   = get_statistic 'Keystone Total'

      loop do
        login

        sleep 10
      end
    end
  end

end

