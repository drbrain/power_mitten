require 'power_mitten/test_case'

class TestPowerMittenTask < PowerMitten::TestCase

  def setup
    super

    @task = @TT.new @options
  end

  def teardown
    super

    PowerMitten::Task.label_orders[@TT] = [:test]
    PowerMitten::Task.labels[@TT].delete_if { |field,| field != :test }
  end

  def test_class_aggregate_description
    assert_equal '%7d RSS', PowerMitten::Task.aggregate_description(:RSS)
    assert_equal '%s',      PowerMitten::Task.aggregate_description(:hostname)
    assert_equal 'pid %5d', PowerMitten::Task.aggregate_description(:pid)

    assert_equal '%7d RSS', @TT.aggregate_description(:RSS)
    assert_equal 'test %d', @TT.aggregate_description(:test)
  end

  def test_class_column_descriptions
    expected = [
      [:pid,      'PID',      '%5d', 5],
      [:hostname, 'Hostname', '%s',  0],
      [:RSS,      'RSS KB',   '%8d', 8],
    ]

    assert_equal expected, PowerMitten::Task.column_descriptions

    expected = [
      [:pid,      'PID',      '%5d', 5],
      [:hostname, 'Hostname', '%s',  0],
      [:RSS,      'RSS KB',   '%8d', 8],
      [:test,     'Test',     '%4d', 4],
    ]

    assert_equal expected, @TT.column_descriptions
  end

  def test_class_describe_label
    @TT.describe_label :test2, 'test %d', ['Test', '%d', 4]

    expected = ['test %d', ['Test', '%d', 4]]

    assert_equal expected, PowerMitten::Task.labels[@TT][:test2]
  end

  def test_class_describe_label_missing_width
    @TT.describe_label :test2, 'test %d', ['Test', '%d']

    expected = ['test %d', ['Test', '%d', 0]]

    assert_equal expected, PowerMitten::Task.labels[@TT][:test2]
  end

  def test_class_label_descriptions
    assert_equal [:pid, :hostname, :RSS],
                 PowerMitten::Task.label_descriptions.keys

    assert_equal [:pid, :hostname, :RSS, :test],
                 @TT.label_descriptions.keys
  end

  def test_class_label_order
    assert_equal [:pid, :hostname, :RSS], PowerMitten::Task.label_order
    assert_equal [:pid, :hostname, :RSS], PowerMitten::Console.label_order

    assert_equal [:pid, :hostname, :RSS, :test],
                 PowerMitten::TestCase::TestTask.label_order
  end

  def test_class_short_name
    assert_equal 'TestTask', @TT.short_name
  end

  def test_control_hosts_initialized
    hosts = @task.control_hosts
    assert_same hosts, @task.control_hosts
  end

  def test_control_hosts_fog
    fog = Object.new

    def fog.servers
      vm = Object.new
      def vm.name() 'Control' end
      def vm.addresses() { '' => { 'addr' => '10.example' } } end
      [vm]
    end

    @task.instance_variable_set :@localhost, false
    @task.instance_variable_set :@fog, fog
    def @task.fog() @fog end

    assert_equal %w[10.example], @task.control_hosts
  end

  def test_control_hosts_fog_no_control
    fog = Object.new

    def fog.servers() [] end

    @task.instance_variable_set :@localhost, false
    @task.instance_variable_set :@fog, fog
    def @task.fog() @fog end

    e = assert_raises RuntimeError do
      @task.control_hosts
    end

    assert_equal 'no control hosts found', e.message
  end

  def test_control_hosts_localhost
    assert_equal %w[127.0.0.1], @task.control_hosts
  end

  def test_description
    description = @task.description

    rss = @task.resident_set_size

    fields = [:klass, :pid, :hostname]
    fields << :RSS if rss

    assert_equal fields.sort, description.keys.sort

    assert_equal PowerMitten::TestCase::TestTask, description[:klass]
    assert_equal $$,                              description[:pid]
    assert_equal @task.hostname,                  description[:hostname]
    assert_kind_of Integer,                       description[:RSS] if rss
  end

end

