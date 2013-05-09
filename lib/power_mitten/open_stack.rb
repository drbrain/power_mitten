require 'json'
require 'net/http/persistent'
require 'time'
require 'uri'

require 'pp'

##
# A basic OpenStack API wrapper

class PowerMitten::OpenStack

  ##
  # A link to a resource returned by the API

  Link = Struct.new :klass, :id, :href do

    ##
    # Creates a new Link from the "bookmark" relation in the link of +json+
    # that will be loaded as an instance of +klass+.

    def self.from_json klass, json
      id = json['id']

      relation   = json['links'].find { |link| link['rel'] == 'self' }
      relation ||= json['links'].find { |link| link['rel'] == 'bookmark' }

      href = URI relation['href']

      new klass, id, href
    end

    ##
    # Follows the link using +openstack+ to make HTTP request.  Returns an
    # instance of the link's #klass.

    def follow openstack
      body = openstack.get href

      klass.new body[klass.resource_name]
    end

  end

  ##
  # An HTTP resource
  #
  # To create a new resource:
  #
  #   Resource.new 'Image',
  #                'id',
  #                'name',
  #                'minDisk',
  #                'minRam',
  #                'status',
  #                'created',
  #                'updated'
  #
  # As with Struct you may supply a block to customize a resource:
  #
  #   Resource.new 'Image', '...' do
  #     def initialize
  #       super # always super
  #     end
  #   end
  #
  # If a field in +fields+ ends with "_link" the result JSON for that field
  # must be a hash containing an "id" and "links" (see ::new for an example).
  # Upon instantiation the resource will automatically create a Link and
  # follow it when the user requests that data.

  class Resource

    ##
    # Maps a JSON field name to a resource class

    RESOURCES      = {} # :nodoc:

    @fields        = nil
    @parent        = Module.nesting[1]
    @resource_name = nil

    class << self

      ##
      # Fields for a Resource subclass.

      attr_reader :fields

      attr_writer :fields # :nodoc:

      ##
      # Used by Link#follow to lookup up the resource class for the link

      attr_reader :resource_name # :nodoc:

    end

    ##
    # Creates a new resource class +class_name+ with the given +fields+.  If a
    # block is given it will be used to customize the created class as
    # Struct.new does.
    #
    # If a field in +fields+ ends with "_link" the result JSON for that field
    # must be a hash containing an "id" and "links" such as:
    #
    #   "image": {
    #     "id": "70a599e0",
    #     "links": [
    #       {
    #         "href": "http://compute.example/tenant/images/70a599e0",
    #         "rel": "bookmark"
    #       }
    #     ]
    #   },
    #
    # Upon instantiation the resource will automatically create a Link and
    # follow it when the user requests that data.
    #
    # The class will be placed in the PowerMitten::OpenStack namespace.

    def self.new class_name, *fields, &block
      resource_name = class_name.downcase

      klass = Class.new self do
        RESOURCES[resource_name] = self

        @fields        = fields
        @resource_name = resource_name

        attr_accessor :openstack

        create_accessors

        def self.new json
          resource_new json
        end
      end

      klass.module_eval(&block) if block

      @parent.const_set class_name, klass

      klass
    end

    ##
    # Creates accessors for a resource.

    def self.create_accessors # :nodoc:
      @fields.each do |field|
        case field
        when /_link$/ then
          accessor = $`

          define_method accessor do
            instance_variable_get("@#{field}").follow @openstack
          end
        end

        attr_reader field
      end
    end

    ##
    # This is the implementation of \::new for a resource.
    #
    # A resource is created from a parsed JSON hash of the resource with the
    # outer name removed.
    #
    # For:
    #
    #   { "image" => { "id" => "1", "name" => "FreeBSD 9.1-RELEASE", ... } }
    #
    # Send:
    #
    #   { "id" => "1", "name" => "FreeBSD 9.1-RELEASE", ... }
    #
    # Sending only the object makes creation more uniform whether the object
    # comes from a single item or a collection.

    def self.resource_new json
      obj = allocate

      @fields.each do |field|
        case field
        when /_link$/ then
          json_field = $`

          klass = RESOURCES[json_field]

          link = Link.from_json klass, json[json_field]

          obj.instance_variable_set "@#{field}", link
        else
          obj.instance_variable_set "@#{field}", json[field]
        end
      end

      obj.send :initialize

      obj
    end

    def initialize # :nodoc:
      @openstack = nil
    end

  end

  ##
  # A server flavor

  Resource.new 'Flavor',
    'id',
    'name',
    'vcpus',
    'ram',
    'disk'

  ##
  # An image used to create a server

  Resource.new 'Image',
    'id',
    'name',
    'created',
    'updated',
    'metadata',
    'minDisk',
    'minRam',
    'progress',
    'status'

  ##
  # A server created by the API

  Resource.new 'Server',
               'id',
               'name',
               'created',
               'updated',
               'addresses',
               'flavor_link',
               'image_link',
               'metadata',
               'progress',
               'status',
               'tenant_id',
               'user_id' do
    def initialize
      super

      @address_list = nil
    end

    def address_list
      @address_list ||= @addresses.map { |type, addrs|
        addrs.map { |addr| addr['addr'] }
      }.flatten
    end
  end

  attr_accessor :cache # :nodoc:
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

    @cache         = {}
    @services      = {}
    @token         = nil
    @token_expires = Time.at 0
  end

  ##
  # Returns the absolute limits

  def absolute_limits
    @absolute_limits || limits['absolute']
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
  # Retrieves your request limits

  def limits
    login

    uri = @services['compute'] + 'limits'

    body = request Net::HTTP::Get, uri

    limits = body['limits']

    @rate_limits     = limits['rate']
    @absolute_limits = limits['absolute']

    limits
  end

  ##
  # Logs in to OpenStack using your authentication server and credentials.
  # This is called automatically so there is no need to call it yourself.

  def login
    return @token if @token and Time.now < @token_expires

    tokens_uri = @keystone_uri + 'tokens'

    req = Net::HTTP::Post.new tokens_uri.path
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
  # Returns the rate limits

  def rate_limits
    @rate_limits || limits['rate']
  end

  ##
  # Makes a request of Net::HTTP request type +klass+ to +uri+.

  def request klass, uri # :nodoc:
    login

    # HACK workaround for broken href values, see:
    # https://support.sl.attcompute.com/requests/1693
    uri = @services['compute'] + uri.path

    last_modified, cached_content_type, cached_body = @cache[uri]

    req = klass.new uri.request_uri
    req['If-Modified-Since'] = last_modified
    req['X-Auth-Token'] = @token
    req['Accept'] =
      'application/vnd.openstack.compute+json;version=2;q=1,application/json;q=0.5,*/*;q=0'

    res = @http.request uri, req

    case res
    when Net::HTTPOK,
         Net::HTTPNonAuthoritativeInformation then
      content_type  = res['Content-Type']
      last_modified = res['Last-Modified']
      body          = res.body

      @cache[uri] = [last_modified, content_type, body] if last_modified
    when Net::HTTPNotModified then
      content_type = cached_content_type
      body         = cached_body
    else
      raise res.inspect
    end

    case content_type
    when 'application/vnd.openstack.compute+json', 'application/json' then
      JSON.parse body
    else
      body
    end
  end

  ##
  # Returns an Array of Server instances for your logged-in tenant.

  def servers
    login

    uri = @services['compute'] + 'servers/detail'

    body = request Net::HTTP::Get, uri

    body['servers'].map do |server|
      vm = Server.new server
      vm.openstack = self
      vm
    end
  end

end

