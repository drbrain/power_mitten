class ATT::CloudGauntlet::Configuration

  @node_types = {}

  attr_accessor :cpu_multiplier
  attr_accessor :maximum_workers
  attr_accessor :name
  attr_reader :services

  def self.new klass
    name = short_name klass

    config = super klass

    @node_types[name] = config

    config
  end

  def self.services_for vm_name
    configuration = @node_types.each_value.find do |config|
      /\A#{Regexp.escape config.name}/ =~ vm_name
    end

    return [] unless configuration

    configuration.services
  end

  def self.short_name klass
    klass.name.split('::').last
  end

  def self.workers_for klass, vcpus
    name = short_name klass

    config = @node_types[name]

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
    @name = self.class.short_name klass

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

