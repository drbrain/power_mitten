require 'json'
require 'net/http/persistent'
require 'time'
require 'uri'

require 'pp'

##
# A basic OpenStack API wrapper

class PowerMitten::OpenStack

  attr_accessor :http # :nodoc:

  ##
  # Services available on OpenStack

  attr_reader :services

  ##
  # Your login token

  attr_reader :token

  ##
  # When your login token expires

  attr_reader :token_expires

  ##
  # A server flavor

  Flavor = Struct.new :id,
                      :name,
                      :vcpus,
                      :ram,
                      :disk do
    def self.field # :nodoc:
      'flavor'
    end

    def self.from_json json # :nodoc:
      new \
        json['id'],
        json['name'],
        json['vcpus'],
        json['ram'],
        json['disk']
    end
  end

  ##
  # An image used to create a server

  Image = Struct.new :id,
                     :name do
    def self.field # :nodoc:
      'image'
    end

    def self.from_json json # :nodoc:
      new \
        json['id'],
        json['name']
    end
  end

  ##
  # A link to a resource returned by the API

  Link = Struct.new :klass, :id, :href do
    ##
    # Creates a new Link from the "bookmark" relation in the linkk of +json+
    # that will be loaded as an instance of +klass+.

    def self.bookmark klass, json
      id = json['id']
      bookmark = json['links'].find { |link| link['rel'] == 'bookmark' }
      href = URI bookmark['href']

      new klass, id, href
    end

    ##
    # Follows the link using +openstack+ to make HTTP request.  Returns an
    # instance of the link's #klass.

    def follow openstack
      body = openstack.get href

      klass.from_json body[klass.field]
    end
  end

  ##
  # A server created by the API

  Server = Struct.new :openstack,
                      :id,
                      :name,
                      :status,
                      :tenant_id,
                      :flavor_link,
                      :image_link,
                      :addresses do
    def self.field # :nodoc:
      'server'
    end

    def self.from_json json # :nodoc:
      # this throws away information
      addresses = json['addresses'].map { |type, addrs|
        addrs.map { |addr| addr['addr'] }
      }.flatten

      Server.new \
        nil,
        json['id'],
        json['name'],
        json['status'],
        json['tenant_id'],
        Link.bookmark(Flavor, json['flavor']),
        Link.bookmark(Image, json['image']),
        addresses
    end

    ##
    # The Flavor for this server

    def flavor
      flavor_link.follow openstack
    end

    ##
    # The Image for this server

    def image
      image_link.follow openstack
    end
  end

  ##
  # Creates a new OpenStack.  The +keystone_uri+ is the authentication server.
  # The +tenant+, +username+ and +password+ are used to authenticate you.
  #
  #   os = PowerMitten::OpenStack.new \
  #     'https://auth.example/v2.0', 'tenant', 'username', 'password'
  #   os.servers.each do |server|
  #     # ...
  #  end

  def initialize keystone_uri, tenant, username, password
    keystone_uri = add_trailing_slash keystone_uri

    @keystone_uri = keystone_uri
    @tenant       = tenant
    @username     = username
    @password     = password

    @http = Net::HTTP::Persistent.new 'power_mitten-openstack'

    @services      = {}
    @token         = nil
    @token_expires = Time.at 0
  end

  ##
  # Adds a trailing slash to +uri+ and returns a new URI.  This makes creating
  # new URIs with URI#+ easier.

  def add_trailing_slash uri # :nodoc:
    uri = uri.to_s

    uri << '/' unless uri.end_with? '/'

    URI uri
  end

  ##
  # Extracts the token and service catalog from +tokens_body+.

  def extract_token tokens_body # :nodoc:
    access = tokens_body['access']
    token  = access['token']

    @token         = token['id']
    @token_expires = Time.iso8601 token['expires']

    service_catalog = access['serviceCatalog']

    service_catalog.each do |endpoint|
      type = endpoint['type']

      public_url = endpoint['endpoints'].first['publicURL']

      public_url << '/' unless public_url.end_with? '/'

      @services[type] = URI public_url
    end

    @token
  end

  ##
  # Performs a GET request for +uri+

  def get uri # :nodoc:
    login

    request Net::HTTP::Get, uri
  end

  ##
  # Logs in to OpenStack using your authentication server and credentials.
  # This is called automatically so there is no need to call it yourself.

  def login
    return @token if @token and Time.now < @token_expires

    tokens_uri = @keystone_uri + 'tokens'

    req = Net::HTTP::Post.new tokens_uri
    req['Content-Type'] = 'application/json'
    req.body = JSON.dump \
      'auth' => {
        'tenantName' => @tenant,
        'passwordCredentials' => {
          'username' => @username,
          'password' => @password,
        },
      }

    res = @http.request tokens_uri, req

    body = JSON.load res.body

    extract_token body
  end

  ##
  # Makes a request of Net::HTTP request type +klass+ to +uri+.

  def request klass, uri # :nodoc:
    login

    # HACK workaround for broken href values, see:
    # https://support.sl.attcompute.com/requests/1693
    uri = @services['compute'] + uri.path

    req = klass.new uri
    req['X-Auth-Token'] = @token
    req['Accept'] =
      'application/vnd.openstack.compute+json;version=2;q=1,application/json;q=0.5,*/*;q=0'

    res = @http.request uri, req

    body =
      case res['Content-Type']
      when 'application/vnd.openstack.compute+json', 'application/json' then
        JSON.parse res.body
      else
        res.body
      end

    case res
    when Net::HTTPOK then
      body
    else
      raise res.inspect
    end
  end

  ##
  # Returns an Array of Server instances for your logged-in tenant.

  def servers
    login

    uri = @services['compute'] + 'servers/detail'

    body = request Net::HTTP::Get, uri

    body['servers'].map do |server|
      vm = Server.from_json server
      vm.openstack = self
      vm
    end
  end

end

