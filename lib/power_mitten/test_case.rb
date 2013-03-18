require 'power_mitten'
require 'minitest/autorun'

class PowerMitten::TestCase < MiniTest::Unit::TestCase

  class TestTask < PowerMitten::Task
    self.label_order = [:test, :pid, :hostname, :RSS]

    describe_label :test, 'test %d', ['Test', '%4d', 4]
  end

  def setup
    @options = {
      localhost: true,

      openstack_auth_url: 'http://auth.example/v2.0/tokens',
      openstack_tenant:   'TENANT',
      openstack_username: 'USERNAME',
      openstack_api_key:  'KEY',
    }
  end

end

