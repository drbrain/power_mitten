class PowerMitten::Configuration

  @task_types = {}

  attr_accessor :cpu_multiplier
  attr_accessor :maximum_workers
  attr_accessor :name
  attr_reader :services

  def self.new klass
    config = super klass

    @task_types[klass.short_name] = config

    config
  end

  def self.services_for vm_name
    configuration = @task_types.each_value.find do |config|
      /\A#{Regexp.escape config.name}/ =~ vm_name
    end

    return [] unless configuration

    configuration.services
  end

  def self.workers_for klass, vcpus
    config = @task_types[klass.short_name]

    cpu_multiplier  = config.cpu_multiplier
    maximum_workers = config.maximum_workers

    workers = vcpus * cpu_multiplier

    return maximum_workers if workers >= maximum_workers

    workers
  end

  ##
  # Creates a new configuration for +klass+
  #
  # The default service has a +cpu_multiplier+ of 1 and a +maximum_workers+
  # count of infinity.

  def initialize klass
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

