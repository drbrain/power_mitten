require 'power_mitten/test_case'
require 'power_mitten/console/row_formatter'

class TestPowerMittenConsoleRowFormatter < PowerMitten::TestCase

  def setup
    super

    @descriptions = [
      { pid:  1234, hostname: 'short',          RSS: 35100, test: 0 },
      { pid: 12345, hostname: 'very-long-name', RSS: 24813, test: 1 },
    ]

    @klass = PowerMitten::TestCase::TestTask
    @rf = PowerMitten::Console::RowFormatter.new @klass
  end

  def test_format
    formatted = @rf.format @descriptions

    expected = <<-EXPECTED.chomp
Test   PID       Hostname   RSS KB
   0  1234          short    35100
   1 12345 very-long-name    24813
    EXPECTED

    assert_equal expected, formatted.join("\n")
  end

  def test_format_rows
    rows = @rf.format_rows @descriptions

    expected = [
      ['Test',   'PID',       'Hostname',   'RSS KB'],
      ['   0', ' 1234',          'short', '   35100'],
      ['   1', '12345', 'very-long-name', '   24813'],
    ]

    assert_equal expected, rows
  end

end

