require 'power_mitten'
require 'pp'
require 'minitest/autorun'

DRb.start_service

##
# A helper for writing power_mitten tests

class PowerMitten::TestCase < MiniTest::Unit::TestCase

  ##
  # A fake task used for tests

  class TestTask < PowerMitten::Task
    describe_label :test, 'test %d', ['Test', '%4d', 4]
  end

  ##
  # \#setup provides:
  #
  # * A default @options instance variable with fake openstack credentials.
  # * @TT which contains PowerMitten::TestCase::TestTask

  def setup
    @TT = PowerMitten::TestCase::TestTask

    @options = {
      localhost: true,
      type:      'TestTask',

      openstack_auth_url: 'http://auth.example/v2.0/tokens',
      openstack_tenant:   'TENANT',
      openstack_username: 'USERNAME',
      openstack_api_key:  'KEY',
    }
  end

  def mu_pp obj # :nodoc:
    s = ''
    s = PP.pp obj, s
    s.force_encoding Encoding.default_external if defined?
    Encoding
    s.chomp
  end

end

