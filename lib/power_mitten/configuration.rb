##
# A task configuration.  This allows the author to define the constraints of
# the task so that PowerMitten can run it appropriately.  The configuration is
# used by PowerMitten::Startup to determine how many service processes can run
# per VM and how to start those services.
#
# For example, an IO-bound task would have a high cpu_multiplier while a
# CPU-bound task may have a cpu_multiplier of one or a fixed maximum_workers
# of 1.
#
# The configuration can also specify related services that should be started
# along with the task.

class PowerMitten::Configuration

  @task_types = {}

  class << self
    attr_reader :task_types # :nodoc:
  end

  ##
  # Number of workers to start per CPU

  attr_accessor :cpu_multiplier

  ##
  # The maximum number of workers to start on a VM

  attr_accessor :maximum_workers

  ##
  # The name of the service

  attr_accessor :name

  ##
  # List of service classes to start with this task.

  attr_reader :services

  ##
  # Creates a new configuration for +klass+
  #
  # The default service has a +cpu_multiplier+ of 1 and a +maximum_workers+
  # count of infinity.

  def self.new klass
    config = super klass

    @task_types[klass.short_name] = config

    config
  end

  ##
  # Returns the services that should be started on +vm_name+.  The +vm_name+
  # may contain trailing information such as a VM number.

  def self.services_for vm_name
    configuration = @task_types.each_value.find do |config|
      /\A#{Regexp.escape config.name}(-|$)/i =~ vm_name
    end

    return [] unless configuration

    configuration.services
  end

  ##
  # Returns the number of workers that should be started for +klass+ given the
  # know numbers of +vcpus+.
  #
  # The number of vcpus is multiplied by the cpu_multiplier.  If this number
  # is larger than maximum_workers then maximum_workers is returned.

  def self.workers_for klass, vcpus
    config = @task_types[klass.short_name]

    cpu_multiplier  = config.cpu_multiplier
    maximum_workers = config.maximum_workers

    workers = vcpus * cpu_multiplier

    return maximum_workers if workers >= maximum_workers

    workers
  end

  def initialize klass # :nodoc:
    @name = klass.short_name

    @cpu_multiplier  = 1
    @maximum_workers = Float::INFINITY
    @services        = [klass]
  end

  ##
  # Adds +klass+ as a service started along with this one

  def add_service klass
    @services << klass
  end

end

