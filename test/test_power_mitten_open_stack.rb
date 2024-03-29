require 'power_mitten/test_case'
require 'power_mitten/open_stack'

class TestPowerMittenOpenStack < PowerMitten::TestCase

  EXPIRES = Time.at(Time.now.to_i + 60).utc

  LOGIN_BODY = {
    "access" => {
      "token" => {
        "id" => "1",
        "expires" => EXPIRES.iso8601,
      },
      "serviceCatalog" => [
        {
          "endpoints" => [
            {
              "publicURL" => "http://volume.example"
            }
          ],
          "type" => "volume"
        },
        {
          "endpoints" => [
            {
              "publicURL" => "http://compute.example"
            }
          ],
          "type" => "compute"
        }
      ]
    }
  }

  class HTTP
    attr_reader :requests
    attr_reader :responses

    def initialize
      @requests  = []
      @responses = []
    end

    def add_response code, body, headers = {}
      klass = Net::HTTPResponse::CODE_TO_OBJ[code]

      res = klass.new '1.1', code, nil
      res.body = body
      res.instance_variable_set :@read, true
      headers.each do |name, value|
        res[name] = value
      end

      @responses << res
    end

    def request uri, req = nil
      req ||= Net::HTTP::Get.new uri.request_uri

      @requests << req
      res = @responses.shift

      raise "out of responses for #{uri}" unless res

      res
    end
  end

  def setup
    super

    @os = PowerMitten::OpenStack.new 'http://auth.example/v2.0', 't', 'u', 'p'

    @http = HTTP.new

    @os.http = @http
  end

  def test_Link_class_from_json
    flavor = PowerMitten::OpenStack::Flavor
    json = {
      'id' => '1',
      'links' => [
        { 'rel' => 'bookmark', 'href' => 'http://compute.example/whatever' },
        { 'rel' => 'self',     'href' => 'http://compute.example/v2/whatever' },
      ]
    }

    link = PowerMitten::OpenStack::Link.from_json flavor, json

    assert_equal flavor,                                    link.klass
    assert_equal '1',                                       link.id
    assert_equal URI('http://compute.example/v2/whatever'), link.href
  end

  def test_Link_follow
    add_login_response

    @http.add_response '200', <<-JSON, 'Content-Type' => 'application/json'
{
  "flavor": {
    "disk": 0,
    "id": "1",
    "name": "m1.tiny",
    "ram": 512,
    "vcpus": 1
  }
}
    JSON

    flavor_klass = PowerMitten::OpenStack::Flavor

    link = PowerMitten::OpenStack::Link.new \
      flavor_klass, '1', URI('http://compute.example/whatever')

    flavor = link.follow @os

    assert_kind_of flavor_klass, flavor

    assert_empty @http.responses
  end

  def test_add_trailing_slash
    assert_equal URI('http://example/path/'),
                 @os.add_trailing_slash('http://example/path')
    assert_equal URI('http://example/path/'),
                 @os.add_trailing_slash(URI('http://example/path'))
  end

  def test_extract_token
    @os.extract_token LOGIN_BODY

    assert_equal '1',     @os.token
    assert_equal EXPIRES, @os.token_expires

    expected = {
      'compute' => URI('http://compute.example'),
      'volume'  => URI('http://volume.example'),
    }

    assert_equal expected, @os.services
  end

  def test_flavors
    add_login_response

    @http.add_response '200', <<-JSON, 'Content-Type' => 'application/json'
{
  "flavors": [
    {
      "id": "1",
      "disk": 0,
      "name": "m1.tiny",
      "ram": 512,
      "vcpus": 1,
      "links": [
        { "rel": "self",     "href": "http://compute.example/v2/t/flavors/1" },
        { "rel": "bookmark", "href": "http://compute.example/t/flavors/1" }
      ]
    }
  ]
}
    JSON

    flavors = @os.flavors

    assert_kind_of Array, flavors

    flavor = flavors.first

    assert_kind_of PowerMitten::OpenStack::Flavor, flavor
  end

  def test_get
    add_login_response

    @http.add_response '200', <<-JSON, 'Content-Type' => 'application/json'
{
  "flavor": {
    "id": "1",
    "name": "m1.tiny"
  }
}
    JSON

    body = @os.get URI('http://compute.example/t/flavors/1')

    expected = {
      'flavor' => {
        'id' => '1',
        'name' => 'm1.tiny',
      }
    }

    assert_equal expected, body

    assert_equal 2, @os.request_count
  end

  def test_limits
    limits = <<-JSON
{
  "limits": {
    "rate": [
      {
        "uri": "*",
        "regex": ".*",
        "limit": [
          {
            "value": 10,
            "verb": "POST",
            "remaining": 2,
            "unit": "MINUTE",
            "next-available": "2011-12-15T22:42:45Z"
          }
        ]
      },
      {
        "uri": "*/servers",
        "regex": "^/servers",
        "limit": [
          {
            "verb": "POST",
            "value": 25,
            "remaining": 24,
            "unit": "DAY",
            "next-available": "2011-12-15T22:42:45Z"
          }
        ]
      }
    ],
    "absolute": {
      "maxTotalRAMSize": 51200,
      "maxServerMeta": 5,
      "maxImageMeta": 5,
      "maxPersonality": 5,
      "maxPersonalitySize": 10240
    }
  }
}
    JSON

    add_login_response

    @http.add_response '200', limits, 'Content-Type' => 'application/json'

    @os.limits

    absolute_limits = {
      'maxImageMeta'       => 5,
      'maxPersonality'     => 5,
      'maxPersonalitySize' => 10240,
      'maxServerMeta'      => 5,
      'maxTotalRAMSize'    => 51200,
    }

    assert_equal absolute_limits, @os.absolute_limits

    rate_limits = [
      { 'uri' => '*',
        'regex' => '.*',
        'limit' => [
          { 'value'          => 10,
            'verb'           => 'POST',
            'remaining'      => 2,
            'unit'           => 'MINUTE',
            'next-available' => '2011-12-15T22:42:45Z', },
        ],
      },
      { 'uri' => '*/servers',
        'regex' => '^/servers',
        'limit' => [
          { 'value'          => 25,
            'verb'           => 'POST',
            'remaining'      => 24,
            'unit'           => 'DAY',
            'next-available' => '2011-12-15T22:42:45Z', },
        ],
      },
    ]

    assert_equal rate_limits, @os.rate_limits
  end

  def test_login
    add_login_response

    token = @os.login

    assert_equal '1', token

    assert_equal 1, @os.request_count
  end

  def test_login_twice
    add_login_response

    token = @os.login

    assert_same token, @os.login

    assert_equal 1, @os.request_count
  end

  def test_login_expired
    add_login_response
    add_login_response

    @os.login
    @os.instance_variable_set :@token_expires, Time.now - 10
    @os.login

    assert_equal EXPIRES, @os.token_expires
    assert_empty @http.responses

    assert_equal 2, @os.request_count
  end

  def test_local_ipv4
    @http.add_response '200', '192.0.2.1', 'Content-Type' => 'text/html'

    assert_equal '192.0.2.1', @os.local_ipv4

    assert_equal 1, @os.request_count
  end

  def test_local_server
    servers = <<-JSON
{
  "servers": [
    {
      "id": "1",
      "addresses": {
        "private": [
          {
            "addr": "192.0.2.1",
            "version": 4
          }
        ]
      },
      "flavor": {
        "id": "2",
        "links": [
          { "rel": "self", "href": "http://compute.example/t/flavors/2" }
        ]
      },
      "image": {
        "id": "3",
        "links": [
          { "rel": "self", "href": "http://compute.example/t/images/3" }
        ]
      }
    }
  ]
}
    JSON

    @http.add_response '200', '192.0.2.1', 'Content-Type' => 'text/html'
    add_login_response
    @http.add_response '200', servers, 'Content-Type' => 'application/json'

    assert_equal %w[192.0.2.1], @os.local_server.address_list
  end

  def test_request
    add_login_response

    uri = URI('http://compute.example/t/flavors/1')
    last_modified = Time.now.httpdate
    headers = {
      'Content-Type' => 'application/json',
      'Last-Modified' => last_modified,
    }
    json = '{ "thing": [ "stuff" ] } '

    @http.add_response '200', json, headers

    body = @os.request Net::HTTP::Get, uri

    expected = { 'thing' => %w[stuff] }

    assert_equal expected, body

    req = @http.requests.last

    assert_equal '1', req['X-Auth-Token']
    assert_equal 'application/vnd.openstack.compute+json;version=2;q=1,application/json;q=0.5,*/*;q=0', req['Accept']

    assert_equal [last_modified, 'application/json', json], @os.cache[uri]

    assert_empty @http.responses

    assert_equal 2, @os.request_count
  end

  def test_request_non_authoritative
    add_login_response

    uri = URI('http://compute.example/t/flavors/1')
    last_modified = Time.now.httpdate
    headers = {
      'Content-Type' => 'application/json',
      'Last-Modified' => last_modified,
    }
    json = '{ "thing": [ "stuff" ] }'

    @http.add_response '203', json, headers

    body = @os.request Net::HTTP::Get, uri

    expected = { 'thing' => %w[stuff] }
    assert_equal expected, body

    assert_equal [last_modified, 'application/json', json], @os.cache[uri]

    assert_equal 2, @os.request_count
  end

  def test_request_not_modified
    add_login_response

    uri = URI 'http://compute.example/t/flavors/1'
    last_modified = Time.at(0).httpdate

    @os.cache[uri] = [
      last_modified,
      'application/json',
      '{ "thing": [ "stuff" ] }',
    ]

    @http.add_response '304', nil

    body = @os.request Net::HTTP::Get, uri

    expected = { 'thing' => %w[stuff] }

    assert_equal expected, body

    req = @http.requests.last

    assert_equal last_modified, req['If-Modified-Since']

    assert_equal 2, @os.request_count
  end

  def test_servers
    add_login_response

    @http.add_response '200', <<-JSON, 'Content-Type' => 'application/json'
{
  "servers": [
    {
      "addresses": {
        "private": [
          {
            "addr": "192.0.2.1",
            "version": 4
          }
        ]
      },
      "flavor": {
        "id": "1",
        "links": [
          {
            "href": "http://compute.example/t/flavors/1",
            "rel": "bookmark"
          }
        ]
      },
      "hostId": "16d193736a5cfdb60c697ca27ad071d6126fa13baeb670fc9d10645e",
      "id": "05184ba3-00ba-4fbc-b7a2-03b62b884931",
      "image": {
        "id": "70a599e0-31e7-49b7-b260-868f441e862b",
        "links": [
          {
            "href": "http://compute.example/t/images/70a599e0-31e7-49b7-b260-868f441e862b",
            "rel": "bookmark"
          }
        ]
      },
      "links": [
        {
          "href": "http://compute.example/v2/t/servers/05184ba3-00ba-4fbc-b7a2-03b62b884931",
          "rel": "self"
        },
        {
          "href": "http://compute.example/t/servers/05184ba3-00ba-4fbc-b7a2-03b62b884931",
          "rel": "bookmark"
        }
      ],
      "metadata": {
        "My Server Name": "Apache1"
      },
      "name": "new-server-test",
      "progress": 0,
      "status": "ACTIVE",
      "tenant_id": "t",
      "updated": "2012-09-07T16:56:37Z",
      "user_id": "fake"
    }
  ]
}
    JSON

    servers = @os.servers

    assert_kind_of Array, servers

    server = servers.first

    assert_kind_of PowerMitten::OpenStack::Server, server
    assert_equal @os, server.openstack
  end

  def add_login_response
    @http.add_response '200', JSON.dump(LOGIN_BODY),
                       'Content-Type' => 'application/json'
  end

end

