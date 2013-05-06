require 'power_mitten/test_case'

class TestPowerMittenConfiguration < PowerMitten::TestCase

  def setup
    super

    @PMC = PowerMitten::Configuration
  end

  def teardown
    super

    @PMC.task_types.delete @TT.short_name
  end

  def test_class_new
    @PMC.new @TT

    assert_equal [@TT], @PMC.services_for(@TT.short_name)
  end

  def test_class_services_for
    @PMC.new @TT

    assert_equal [@TT], @PMC.services_for('TestTask')
    assert_equal [@TT], @PMC.services_for('TestTask-0')

    assert_empty @PMC.services_for('TestTaskTwo')
  end

  def test_class_services_for_multiple
    config = @PMC.new @TT
    config.add_service PowerMitten::RingServer

    assert_equal [@TT, PowerMitten::RingServer], @PMC.services_for('TestTask')
  end

  def test_class_services_for_none
    assert_empty @PMC.services_for('unknown')
  end

  def test_class_workers_for
    config = @PMC.new @TT
    config.cpu_multiplier = 2
    config.maximum_workers = 5

    assert_equal 2, @PMC.workers_for(@TT, 1)
    assert_equal 4, @PMC.workers_for(@TT, 2)
    assert_equal 5, @PMC.workers_for(@TT, 3)
  end

  def test_initialize
    config = @PMC.new @TT

    assert_equal 1,               config.cpu_multiplier
    assert_equal Float::INFINITY, config.maximum_workers
    assert_equal [@TT],           config.services
  end

  def test_add_service
    config = @PMC.new @TT
    config.add_service PowerMitten::RingServer

    assert_equal [@TT, PowerMitten::RingServer], config.services
  end

end

