require 'power_mitten/test_case'

class TestPowerMittenNode < PowerMitten::TestCase

  def setup
    super

    @node  = PowerMitten::Node.new @options
  end

  def test_class_aggregate_description
    assert_equal '%7d RSS', PowerMitten::Node.aggregate_description(:RSS)
    assert_equal '%s',      PowerMitten::Node.aggregate_description(:hostname)
    assert_equal 'pid %5d', PowerMitten::Node.aggregate_description(:pid)

    assert_equal '%7d RSS',
                 PowerMitten::TestCase::TestNode.aggregate_description(:RSS)
    assert_equal 'test %d',
                 PowerMitten::TestCase::TestNode.aggregate_description(:test)
  end

  def test_class_column_descriptions
    expected = [
      [:pid,      'PID',      '%5d', 5],
      [:hostname, 'Hostname', '%s',  0],
      [:RSS,      'RSS KB',   '%8d', 8],
    ]

    assert_equal expected, PowerMitten::Node.column_descriptions

    expected = [
      [:test,     'Test',     '%4d', 4],
      [:pid,      'PID',      '%5d', 5],
      [:hostname, 'Hostname', '%s',  0],
      [:RSS,      'RSS KB',   '%8d', 8],
    ]

    assert_equal expected, PowerMitten::TestCase::TestNode.column_descriptions
  end

  def test_class_describe_label
    PowerMitten::Node.describe_label :test2, 'test %d', ['Test', '%d', 4]

    expected = ['test %d', ['Test', '%d', 4]]

    assert_equal expected, PowerMitten::Node.labels[PowerMitten::Node][:test2]
  ensure
    PowerMitten::Node.labels[PowerMitten::Node].delete(:test2)
  end

  def test_class_describe_label_missing_width
    PowerMitten::Node.describe_label :test2, 'test %d', ['Test', '%d']

    expected = ['test %d', ['Test', '%d', 0]]

    assert_equal expected, PowerMitten::Node.labels[PowerMitten::Node][:test2]
  ensure
    PowerMitten::Node.labels[PowerMitten::Node].delete(:test2)
  end

  def test_class_label_descriptions
    assert_equal [:RSS, :hostname, :pid],
                 PowerMitten::Node.label_descriptions.keys

    assert_equal [:RSS, :hostname, :pid, :test],
                 PowerMitten::TestCase::TestNode.label_descriptions.keys
  end

  def test_class_label_order
    assert_equal [:pid, :hostname, :RSS], PowerMitten::Node.label_order
    assert_equal [:pid, :hostname, :RSS], PowerMitten::Console.label_order

    assert_equal [:test, :pid, :hostname, :RSS],
                 PowerMitten::TestCase::TestNode.label_order
  end

  def test_description
    description = @node.description

    rss = @node.resident_set_size

    fields = [:klass, :pid, :hostname]
    fields << :RSS if rss

    assert_equal fields.sort, description.keys.sort

    assert_equal PowerMitten::Node, description[:klass]
    assert_equal $$,                description[:pid]
    assert_equal @node.hostname,    description[:hostname]
    assert_kind_of Integer,         description[:RSS] if rss
  end

end

