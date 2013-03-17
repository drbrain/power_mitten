require 'ringy_dingy/ring_server'

class PowerMitten::RingServer < PowerMitten::Node

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  attr_reader :expirations
  attr_reader :registrations
  attr_reader :service_registry

  def initialize options
    super

    @ring_server      = nil
    @service_registry = Rinda::TupleSpace.new

    @expirations   = 0
    @registrations = 0
  end

  def description # :nodoc:
    service_count = @service_registry.read_all([:name, nil, nil, nil]).size

    "#{service_count}\u2713 #{@registrations}\u2913 #{@expirations}\u2620 " +
      super
  end

  def run
    notice "listening on #{DRb.uri}"

    Thread.start do
      notifier = @service_registry.notify 'write', [:name, nil, DRbObject, nil]

      notifier.each do |(_, (_, name, service, description))|
        @registrations += 1

        notice "registered %p, %p at URI: %s ref: %d" %
          [name, description, service.__drburi, service.__drbref]
      end
    end

    Thread.start do
      notifier = @service_registry.notify 'delete', [:name, nil, DRbObject, nil]

      notifier.each do |(_, (_, name, service, description))|
        @expirations += 1

        notice "expired %p, %p at URI: %s ref: %d" %
          [name, description, service.__drburi, service.__drbref]
      end
    end

    @ring_server = Rinda::RingServer.new @service_registry

    @service_registry.write [
      :name, 'Mitten-RingServer', DRb::DRbObject.new(self),
      'the current ring server'
    ]

    DRb.thread.join
  end

end

