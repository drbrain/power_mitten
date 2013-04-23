require 'power_mitten/test_case'
require 'power_mitten'

class TestPowerMittenStatistics < PowerMitten::TestCase

  def setup
    super

    @options[:name] = 'test'

    @stats = PowerMitten::Statistics.new @options
  end

  def test_add_value
    assert_equal    0,   @stats.items
    assert_in_delta 0.0, @stats.mean

    @stats.add_value 4

    assert_equal    1,   @stats.items
    assert_in_delta 4.0, @stats.mean

    @stats.add_value 7

    assert_equal    2,     @stats.items
    assert_in_delta 5.500, @stats.mean
    assert_in_delta 4.500, @stats.sample_variance
    assert_in_delta 2.121, @stats.standard_deviation

    @stats.add_value 13

    assert_equal     3,     @stats.items
    assert_in_delta  8.000, @stats.mean
    assert_in_delta 21.000, @stats.sample_variance
    assert_in_delta  4.583, @stats.standard_deviation

    @stats.add_value 16

    assert_equal     4,     @stats.items
    assert_in_delta 10.000, @stats.mean
    assert_in_delta 30.000, @stats.sample_variance
    assert_in_delta  5.477, @stats.standard_deviation
  end

  def test_add_value_catastrophic_cancellation
    assert_equal    0,   @stats.items
    assert_in_delta 0.0, @stats.mean

    @stats.add_value 4 + 10e8

    assert_equal      1,        @stats.items
    assert_in_epsilon 4 + 10e8, @stats.mean

    @stats.add_value 7 + 10e8

    assert_equal      2,          @stats.items
    assert_in_epsilon 5.5 + 10e8, @stats.mean
    assert_in_epsilon 4.5,        @stats.sample_variance

    @stats.add_value 13 + 10e8

    assert_equal       3,        @stats.items
    assert_in_epsilon  8 + 10e8, @stats.mean
    assert_in_epsilon 21.0,      @stats.sample_variance

    @stats.add_value 16 + 10e8

    assert_equal         4,   @stats.items
    assert_in_epsilon 10e8,   @stats.mean
    assert_in_epsilon 30.0,   @stats.sample_variance
  end

end

