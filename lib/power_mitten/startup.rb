class PowerMitten::Startup < PowerMitten::Task

  def initialize options = {}
    super

    @local_ip = nil
    @threads  = nil
    @running  = true

    @options  = options
    @workers  = @options[:workers]
  end

  def run
    name = local_name

    notice "this is a #{name} task"

    services = PowerMitten::Configuration.services_for name

    @threads = start_services services

    trap 'INT'  do stop_services end
    trap 'TERM' do stop_services end

    @threads.each do |thread|
      thread.join
    end
  end

  def start_services services
    services.map do |service|
      start_service service, workers(service), @options
    end.flatten
  end

  def workers service
    return @workers if @workers.nonzero?

    PowerMitten::Configuration.workers_for service, local_vcpus
  end

end

