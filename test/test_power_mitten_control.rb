require 'power_mitten/test_case'

class TestPowerMittenControl < PowerMitten::TestCase

  def setup
    super

    @control = PowerMitten::Control.new @options
    @rl      = RingyDingy::Lookup.new %w[127.0.0.1]
    @ts      = Rinda::TupleSpace.new

    @control.ring_lookup = @rl

    ring_finger = @rl.ring_finger
    ring_finger.instance_variable_set :@tuple_space, @ts

    def ring_finger.lookup_ring_any
      @tuple_space
    end
  end

  def test_add_service
    service = @control.add_service Object, 'object'

    assert_instance_of Object, service

    assert_same service, @control.add_service(Object, 'object')
  end

  def test_ping
    assert_in_delta Time.now, @control.ping, 1
  end

end

