class ATT::CloudGauntlet::Configuration

  @node_types = {}

  attr_accessor :cpu_multiplier
  attr_accessor :maximum_workers
  attr_accessor :name
  attr_accessor :services

  def self.new name
    config = super name

    @node_types[name] = config

    config
  end

  def self.services_for name
    configuration = @node_types.each_value.find do |config|
      /#{Regexp.escape config.name}/ =~ name
    end

    return [] unless configuration

    configuration.services
  end

  def initialize name
    @name = name

    @cpu_multiplier  = 1
    @maximum_workers = Float::INFINITY
    @services        = []
  end

end

