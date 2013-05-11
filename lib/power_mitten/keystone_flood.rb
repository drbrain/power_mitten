##
# Logs in to keystone as rapidly as possible using a separate HTTP connection
# for each request.
#
# Uses the keystone_username, keystone_password and keystone_tenant values
# from the configuration file.

class PowerMitten::KeystoneFlood < PowerMitten::Task

  file_limit, = Process.getrlimit Process::RLIMIT_NOFILE

  config = PowerMitten::Configuration.new self
  config.maximum_workers = file_limit / 2

  describe_label :requests,   '%8d', ['Requests',   '%8d', 8]
  describe_label :successful, '%8d', ['Successful', '%8d', 8]

  ##
  # Creates a new KeystoneFlood service.  The service will use the following
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
    require 'socket'
    require 'uri'

    super

    url = URI options['keystone_url']
    url += '/v2.0/tokens'

    @keystone_ssl     = url.scheme.downcase == 'https'
    @keystone_host    = Resolv.getaddress url.host
    @keystone_port    = url.port
    @keystone_path    = url.path
    @keystone_request = keystone_request options

    require 'openssl' if @keystone_ssl

    @requests   = 0
    @successful = 0
  end

  def description # :nodoc:
    super do |description|
      description[:requests]   = @requests
      description[:successful] = @successful
    end
  end

  ##
  # Creates an HTTP/1.1 request string that can cached.

  def keystone_request options # :nodoc:
    keystone_login = {
      'auth' => {
        'passwordCredentials' => {
          'username' => options['keystone_username'],
          'password' => options['keystone_password'],
        },
        'tenantName' => options['keystone_tenant'],
      }
    }

    body = JSON.dump keystone_login

    <<-HTTP
POST #{@keystone_path} HTTP/1.1\r
Connection: close\r
Content-Length: #{body.length}\r
Content-Type: application/json\r
Host: #{@keystone_host}:#{@keystone_port}\r
\r
#{body}
    HTTP
  end

  ##
  # Logs in to keystone

  def login
    socket = make_socket

    socket.write @keystone_request

    @requests += 1

    status_line = socket.readline

    socket.close

    @successful += 1 if status_line == "HTTP/1.1 200 OK\r\n"

    notice "#{@requests} requests, #{@successful} successful" if
      @requests % 100 == 0
  end

  ##
  # Creates a socket for this keystone.  If an SSL connection is necessary no
  # certificate validation will be performed.

  def make_socket # :nodoc:
    socket = TCPSocket.open @keystone_host, @keystone_port

    socket = OpenSSL::SSL::SSLSocket.new socket if @keystone_ssl

    socket
  end

  def run # :nodoc:
    super do
      while true do
        login
      end
    end
  end

end

