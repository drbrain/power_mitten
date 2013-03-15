class PowerMitten::Startup < PowerMitten::Node

  def initialize options = {}
    super

    @local_ip = nil
    @threads  = nil
    @running  = true

    @options  = options
    @workers  = @options[:workers]
  end

  def fork_child service, workers
    pid = fork do
      Process.setsid

      trap 'INT',  'DEFAULT'
      trap 'TERM', 'DEFAULT'

      $PROGRAM_NAME = "mitten #{service.short_name}"

      service.new(@options).run
    end

    notice "forked #{service.name} at #{pid}"

    pid
  end

  def run
    name = local_name

    notice "this is a #{name} node"

    services = PowerMitten::Configuration.services_for name

    @threads = start_services services

    trap 'INT'  do stop_services end
    trap 'TERM' do stop_services end

    @threads.each do |thread|
      thread.join
    end
  end

  def start_service service
    workers = workers service

    ok_signals = Signal.list.values_at 'TERM', 'INT'

    workers.times.map do
      Thread.new do
        while @running do
          pid = fork_child service, workers

          Thread.current[:pid] = pid

          _, status = Process.wait2 pid

          notice "service #{service} #{status}"

          break if status.success?
          break if ok_signals.include?(status.termsig)
        end
      end
    end
  end

  def start_services services
    services.map do |service|
      start_service service
    end.flatten
  end

  def stop_services
    @running = false

    @threads.each do |thread|
      pid = thread[:pid]

      next unless pid

      notice "shutting down #{pid}"

      begin
        Process.kill 'TERM', pid
      rescue Errno::ESRCH
        notice "process #{pid} not found"
      end
    end
  end

  def workers service
    return @workers if @workers.nonzero?

    PowerMitten::Configuration.workers_for service, local_vcpus
  end

end

