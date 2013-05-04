require 'power_mitten/test_case'

class TestPowerMittenConfiguration < PowerMitten::TestCase

  def setup
    super

    @PMC = PowerMitten::Configuration
  end

  def test_class_new
    config = @PMC.new @TT

    assert_equal [@TT], @PMC.services_for(@TT.short_name)
  end

end

