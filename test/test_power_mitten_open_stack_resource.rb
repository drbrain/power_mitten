require 'power_mitten/test_case'
require 'power_mitten/open_stack'

class TestPowerMittenOpenStackResource < PowerMitten::TestCase

  def setup
    super

    @Resource = PowerMitten::OpenStack::Resource
    @Link     = PowerMitten::OpenStack::Link
  end

  def test_class_new
    r = @Resource.new 'Testnew', 'one' do
      def two
        2
      end
    end

    assert_match %r%Testnew$%, r.name
    assert_same r, @Resource::RESOURCES['testnew']

    assert_includes r.instance_methods(false), :one
    assert_includes r.instance_methods(false), :two
    assert_includes r.instance_methods(false), :openstack
    assert_includes r.instance_methods(false), :openstack=
  end

  def test_class_create_resources
    r = Class.new @Resource
    r.fields = %w[four five_link]
    r.create_accessors

    assert_includes r.instance_methods(false), :four
    assert_includes r.instance_methods(false), :five
    assert_includes r.instance_methods(false), :five_link
  end

  def test_class_resource_new
    r = @Resource.new 'Testresourcenew', 'one', 'two_link'

    obj = r.new 'one' => 1,
                'two' => {
                  'id'    => '3',
                  'links' => [
                    'rel'  => 'bookmark',
                    'href' => 'http://compute.example/two/3'
                  ]
                }

    assert_instance_of r, obj

    assert_equal 1, obj.one

    link = @Link.new nil, '3', URI('http://compute.example/two/3')

    assert_equal link, obj.two_link
  end

end

