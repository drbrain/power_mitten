require 'power_mitten/test_case'

class TestPowerMittenTask < PowerMitten::TestCase

  def setup
    super

    @task  = PowerMitten::Task.new @options
  end

  def test_class_aggregate_description
    assert_equal '%7d RSS', PowerMitten::Task.aggregate_description(:RSS)
    assert_equal '%s',      PowerMitten::Task.aggregate_description(:hostname)
    assert_equal 'pid %5d', PowerMitten::Task.aggregate_description(:pid)

    assert_equal '%7d RSS',
                 PowerMitten::TestCase::TestTask.aggregate_description(:RSS)
    assert_equal 'test %d',
                 PowerMitten::TestCase::TestTask.aggregate_description(:test)
  end

  def test_class_column_descriptions
    expected = [
      [:pid,      'PID',      '%5d', 5],
      [:hostname, 'Hostname', '%s',  0],
      [:RSS,      'RSS KB',   '%8d', 8],
    ]

    assert_equal expected, PowerMitten::Task.column_descriptions

    expected = [
      [:test,     'Test',     '%4d', 4],
      [:pid,      'PID',      '%5d', 5],
      [:hostname, 'Hostname', '%s',  0],
      [:RSS,      'RSS KB',   '%8d', 8],
    ]

    assert_equal expected, PowerMitten::TestCase::TestTask.column_descriptions
  end

  def test_class_describe_label
    PowerMitten::Task.describe_label :test2, 'test %d', ['Test', '%d', 4]

    expected = ['test %d', ['Test', '%d', 4]]

    assert_equal expected, PowerMitten::Task.labels[PowerMitten::Task][:test2]
  ensure
    PowerMitten::Task.labels[PowerMitten::Task].delete(:test2)
  end

  def test_class_describe_label_missing_width
    PowerMitten::Task.describe_label :test2, 'test %d', ['Test', '%d']

    expected = ['test %d', ['Test', '%d', 0]]

    assert_equal expected, PowerMitten::Task.labels[PowerMitten::Task][:test2]
  ensure
    PowerMitten::Task.labels[PowerMitten::Task].delete(:test2)
  end

  def test_class_label_descriptions
    assert_equal [:RSS, :hostname, :pid],
                 PowerMitten::Task.label_descriptions.keys

    assert_equal [:RSS, :hostname, :pid, :test],
                 PowerMitten::TestCase::TestTask.label_descriptions.keys
  end

  def test_class_label_order
    assert_equal [:pid, :hostname, :RSS], PowerMitten::Task.label_order
    assert_equal [:pid, :hostname, :RSS], PowerMitten::Console.label_order

    assert_equal [:test, :pid, :hostname, :RSS],
                 PowerMitten::TestCase::TestTask.label_order
  end

  def test_description
    description = @task.description

    rss = @task.resident_set_size

    fields = [:klass, :pid, :hostname]
    fields << :RSS if rss

    assert_equal fields.sort, description.keys.sort

    assert_equal PowerMitten::Task, description[:klass]
    assert_equal $$,                description[:pid]
    assert_equal @task.hostname,    description[:hostname]
    assert_kind_of Integer,         description[:RSS] if rss
  end

end

