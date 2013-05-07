##
# The Startup task wraps a service task and keeps it alive in the face of
# bugs.
#
# The child tasks will be shut down upon receipt of an INT or TERM signal.

class PowerMitten::Startup < PowerMitten::Task

  ##
  # Creates a new Startup task.  The number of workers to start can be
  # specified via +options+ through the :workers key.  If unspecified this
  # will be calculated based on the task configuration.

  def initialize options
    super

    @local_ip = nil

    @options  = options
    @workers  = @options[:workers]
  end

  ##
  # Using the local_name of this VM (or type if running as localhost), a
  # set of services are spawned based on the service configuration.  The
  # startup task will exit when all services have shut themselves down.
  #
  # These services will be automatically restarted, see
  # PowerMitten::Task#start_service for the restart conditions.

  def run
    name = local_name

    notice "this is a #{name} task"

    services = PowerMitten::Configuration.services_for name

    start_services services

    trap 'INT'  do stop_services end
    trap 'TERM' do stop_services end

    @threads.each do |thread|
      thread.join
    end
  end

  ##
  # Starts +services+

  def start_services services
    services.each do |service|
      start_service service, workers(service), @options
    end
  end

  ##
  # Calculates the number of workers to start based on the task configuration
  # unless an explicit number of workers was given.

  def workers service
    return @workers if @workers.nonzero?

    PowerMitten::Configuration.workers_for service, local_vcpus
  end

end

