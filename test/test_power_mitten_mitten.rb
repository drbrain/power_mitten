require 'power_mitten/test_case'
require 'tempfile'
require 'tmpdir'

class TestPowerMittenMitten < PowerMitten::TestCase

  def setup
    super

    @home = ENV['HOME']
  end

  def teardown
    super

    ENV['HOME'] = @home
  end

  def test_class_load_configuration_alternate
    Tempfile.open 'dot_power_mitten' do |io|
      io.write <<-DOT_POWER_MITTEN
openstack_auth_url: https://compute.example/v2.0/tokens
openstack_tenant:   TENANT
openstack_username: USERNAME
openstack_api_key:  PASSWORD
swift_uri:      https://storage.example/auth/
swift_username: TENANT:USERNAME
swift_key:      PASSWORD
      DOT_POWER_MITTEN

      io.flush

      loaded = PowerMitten::Mitten.load_configuration configuration: io.path

      expected = {
        configuration: io.path,

        openstack_api_key:  'PASSWORD',
        openstack_auth_url: 'https://compute.example/v2.0/tokens',
        openstack_tenant:   'TENANT',
        openstack_username: 'USERNAME',

        swift_uri:      URI('https://storage.example/auth/'),
        swift_username: 'TENANT:USERNAME',
        swift_key:      'PASSWORD',
      }

      assert_equal expected, loaded
    end
  end

  def test_class_load_configuration_default
    Dir.mktmpdir do |home|
      ENV['HOME'] = home

      dot_power_mitten = <<-DOT_POWER_MITTEN
openstack_auth_url: https://compute.example/v2.0/tokens
openstack_tenant:   TENANT
openstack_username: USERNAME
openstack_api_key:  PASSWORD
swift_uri:      https://storage.example/auth/
swift_username: TENANT:USERNAME
swift_key:      PASSWORD
other: value
      DOT_POWER_MITTEN

      File.write File.join(home, '.power_mitten'), dot_power_mitten

      loaded = PowerMitten::Mitten.load_configuration localhost: true

      expected = {
        localhost: true,

        openstack_api_key:  'PASSWORD',
        openstack_auth_url: 'https://compute.example/v2.0/tokens',
        openstack_tenant:   'TENANT',
        openstack_username: 'USERNAME',

        swift_uri:      URI('https://storage.example/auth/'),
        swift_username: 'TENANT:USERNAME',
        swift_key:      'PASSWORD',

        'other' => 'value',
      }

      assert_equal expected, loaded
    end
  end

  def test_class_load_configuration_default_no_file
    Dir.mktmpdir do |home|
      ENV['HOME'] = home

      options = PowerMitten::Mitten.load_configuration localhost: true

      expected = {
        localhost: true
      }

      assert_equal expected, options
    end
  end

  def test_class_load_configuration_missing_entry
    Tempfile.open 'dot_power_mitten' do |io|
      io.puts 'foo: bar'

      io.flush

      _, err = capture_io do
        assert_raises SystemExit do
          PowerMitten::Mitten.load_configuration configuration: io.path
        end
      end

      assert_match %r%missing openstack_api_key%, err
    end
  end

end

