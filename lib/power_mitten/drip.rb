class PowerMitten::Drip < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  ##
  # An accessor for the drip instance

  attr_reader :drip

  def initialize options
    super

    require 'drip'

    @name = ['power_mitten', options[:name]].compact.join '-'
    @type = 'Drip'

    path = File.join '~/.drip', @name
    @drip = Drip.new File.expand_path path
  end

  def run
    service = nil

    super do
      service ||= register @drip, 'drip'

      service.thread.join
    end
  end

end

