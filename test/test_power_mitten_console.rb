require 'power_mitten/test_case'
require 'power_mitten/console/row_formatter'

class TestPowerMittenConsole < PowerMitten::TestCase

  def setup
    super

    @console = PowerMitten::Console.new @options
  end

  def test_row_formatter_for
    @console.reinitialize

    description = {
      klass: PowerMitten::TestCase::TestNode,
    }

    row_formatter = @console.row_formatter_for description

    expected =
      PowerMitten::Console::RowFormatter.new PowerMitten::TestCase::TestNode

    assert_equal expected, row_formatter
  end

end

