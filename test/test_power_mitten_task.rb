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
      [:pid,                'PID',      '%5d', 5],
      [:hostname,           'Hostname', '%s',  0],
      [:openstack_requests, 'OS Reqs',  '%d',  0],
      [:RSS,                'RSS KB',   '%8d', 8],
    ]

    assert_equal expected, PowerMitten::Task.column_descriptions

    expected = [
      [:pid,                'PID',      '%5d', 5],
      [:hostname,           'Hostname', '%s',  0],
      [:openstack_requests, 'OS Reqs',  '%d',  0],
      [:RSS,                'RSS KB',   '%8d', 8],
      [:test,               'Test',     '%4d', 4],
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
    assert_equal [:pid, :hostname, :openstack_requests, :RSS],
                 PowerMitten::Task.label_descriptions.keys

    assert_equal [:pid, :hostname, :openstack_requests, :RSS, :test],
                 @TT.label_descriptions.keys
  end

  def test_class_label_order
    default = [:pid, :hostname, :openstack_requests, :RSS]
    assert_equal default, PowerMitten::Task.label_order
    assert_equal default, PowerMitten::Console.label_order

    assert_equal default + [:test], PowerMitten::TestCase::TestTask.label_order
  end

  def test_class_short_name
    assert_equal 'TestTask', @TT.short_name
  end

  def test_description
    description = @task.description

    rss = @task.resident_set_size

    fields = [:RSS, :group, :hostname, :klass, :openstack_requests, :pid]

    assert_equal fields, description.keys.sort

    assert_equal 'Mitten',                description[:group]
    assert_equal @task.hostname,          description[:hostname]
    assert_equal DRb::DRbObject.new(@TT), description[:klass]
    assert_equal 0,                       description[:openstack_requests]
    assert_equal $$,                      description[:pid]
    assert_kind_of Integer,               description[:RSS]
  end

  def test_fork_child
    pid = @task.fork_child @TT, @options

    Process.kill 'TERM', pid

    _, status = Process.wait2 pid

    assert status.signaled?
    assert_equal Signal.list['TERM'], status.termsig
  rescue Exception => e
    begin
      Process.kill 'KILL', pid if pid
    rescue Errno::ESRCH
    end

    raise e
  end

  def test_hostname
    assert_equal Socket.gethostname.split('.', 2).first, @task.hostname
  end

  def test_local_name
    assert_equal 'TestTask', @task.local_name
  end

  def test_local_name_openstack
    skip 'currently uses fog, switch to metadata API'

    assert_equal :junk, @task.local_name
  end

  def test_pid
    assert_equal $PID, @task.pid
  end

  def test_register
    ts = Rinda::TupleSpace.new
    @task.instance_variable_set :@ring_lookup, ts

    obj = Object.new

    @task.register obj, 'test_register_object'

    tuple = [
      :name,
      'test_register_object',
      DRb::DRbObject,
      "#{Socket.gethostname}_#{$$}"
    ]

    assert ts.read tuple
  end

  def test_short_name
    assert_equal 'TestTask', @task.short_name
  end

  def test_start_service
    assert_equal 0, @task.threads.length

    @task.start_service @TT, 2

    assert_equal 2,    @task.threads.length

    thread = @task.threads[0]
    Thread.pass until thread[:pid]
    refute_equal $PID, @task.threads[0][:pid]

    thread = @task.threads[1]
    Thread.pass until thread[:pid]
    refute_equal $PID, @task.threads[1][:pid]
  ensure
    @task.stop_services
  end

  def test_start_service_hup
    @task.start_service @TT, 1

    thread = @task.threads.first

    Thread.pass until thread[:pid]

    pid = thread[:pid]

    Process.kill 'HUP', pid

    Thread.pass while thread[:pid] == pid

    refute_equal pid, thread[:pid]
  ensure
    @task.stop_services
  end

  def test_start_service_int
    capture_io do
      @task.start_service @TT, 1

      thread = @task.threads.first

      Thread.pass until thread[:pid]

      pid = thread[:pid]

      Process.kill 'INT', pid

      begin
        Process.wait pid
      rescue Errno::ECHILD
      end

      assert_equal pid, thread[:pid]
    end
  ensure
    @task.stop_services
  end

  def test_start_service_kill
    capture_io do
      @task.start_service @TT, 1

      thread = @task.threads.first

      Thread.pass until thread[:pid]

      pid = thread[:pid]

      Process.kill 'KILL', pid

      sleep 0.1

      begin
        Process.kill 'KILL', pid
        flunk "#{pid} not signaled"
      rescue Errno::ESRCH
        assert true
      end
    end
  ensure
    @task.stop_services
  end

  def test_start_service_term
    capture_io do
      @task.start_service @TT, 1

      thread = @task.threads.first

      Thread.pass until thread[:pid]

      pid = thread[:pid]

      Process.kill 'TERM', pid

      begin
        Process.wait pid
      rescue Errno::ECHILD
      end

      assert_equal pid, thread[:pid]
    end
  ensure
    @task.stop_services
  end

  def test_stop_services
    @task.start_service @TT, 2

    Thread.pass until @task.threads.all? { |thread| thread[:pid] }

    pids = @task.threads.map { |thread| thread[:pid] }

    @task.stop_services

    sleep 0.1

    pids.each do |pid|
      begin
        Process.kill 'KILL', pid
        flunk "#{pid} not signaled"
      rescue Errno::ESRCH
        assert true
      end
    end
  end

end

