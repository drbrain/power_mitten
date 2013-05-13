require 'power_mitten/test_case'
require 'power_mitten/console/row_formatter'

class TestPowerMittenConsole < PowerMitten::TestCase

  def setup
    super

    @console = PowerMitten::Console.new @options
  end

  def test_collate_descriptions
    services = [
      ['Mitten-Console', 'Mitten'],
      ['Mitten-Console', 'Mitten'],
      ['Mitten-control', 'Mitten'],
      ['Queue-gem_files', 'Queue'],
      ['Queue-gem_names', 'Queue'],
    ]

    collated = @console.collate_descriptions services

    expected = {
      'Mitten-Console' => [
        ['Mitten-Console', 'Mitten'],
        ['Mitten-Console', 'Mitten'],
      ],
      'Mitten-control' => [
        ['Mitten-control', 'Mitten'],
      ],
      'Queue' => [
        ['Queue-gem_files', 'Queue'],
        ['Queue-gem_names', 'Queue'],
      ],
    }

    assert_equal expected, collated
  end

  def test_row_formatter_for
    @console.reinitialize

    description = {
      klass: PowerMitten::TestCase::TestTask,
    }

    row_formatter = @console.row_formatter_for description

    expected =
      PowerMitten::Console::RowFormatter.new PowerMitten::TestCase::TestTask

    assert_equal expected, row_formatter
  end

  def test_service_descriptions
    s1 = Object.new
    def s1.description() { name: 'service 1', group: 'group' } end
    s2 = Object.new
    def s2.description() { name: 'service 2', group: 'group' } end
    s3 = Object.new
    def s3.description() raise DRb::DRbConnError end

    services = [
      [:name, 's1', s1, ''],
      [:name, 's2', s2, ''],
      [:name, 's3', s3, ''],
    ]

    descriptions = @console.service_descriptions services

    expected = [
      ['s1', 'group', { name: 'service 1', group: 'group' }],
      ['s2', 'group', { name: 'service 2', group: 'group' }],
    ]

    assert_equal expected, descriptions
  end

  def test_sort_descriptions
    description = [
      ['Mitten-c'],
      ['Mitten-control'],
      ['Mitten-d'],
    ]

    sorted = @console.sort_descriptions description

    expected = [
      ['Mitten-control'],
      ['Mitten-c'],
      ['Mitten-d'],
    ]

    assert_equal expected, sorted
  end

end

