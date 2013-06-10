require 'power_mitten/test_case'
require 'power_mitten/console/row_formatter'

class TestPowerMittenConsoleRowFormatter < PowerMitten::TestCase

  def setup
    super

    @descriptions = [
      { pid:  1234, hostname: 'short',          RSS: 35100,
        openstack_requests: 1, test: 0 },
      { pid: 12345, hostname: 'very-long-name', RSS: 24813,
        openstack_requests: 2, test: 1 },
    ]

    @klass = PowerMitten::TestCase::TestTask
    @rf = PowerMitten::Console::RowFormatter.new @klass
  end

  def test_format
    formatted = @rf.format @descriptions

    expected = <<-EXPECTED.chomp
  PID       Hostname OS Reqs   RSS KB Test
 1234          short       1    35100    0
12345 very-long-name       2    24813    1
    EXPECTED

    assert_equal expected, formatted.join("\n")
  end

  def test_format_rows
    rows = @rf.format_rows @descriptions

    expected = [
      [  'PID',       'Hostname', 'OS Reqs',   'RSS KB', 'Test',],
      [' 1234',          'short',       '1', '   35100', '   0',],
      ['12345', 'very-long-name',       '2', '   24813', '   1',],
    ]

    assert_equal expected, rows
  end

end

