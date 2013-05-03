require 'ringy_dingy/ring_server'

##
# A RingServer task.  The RingServer is used for registration and some
# communication.

class PowerMitten::RingServer < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  self.label_order = PowerMitten::Task.label_order + [
    :service_count,
    :registrations,
    :expirations,
  ]

  describe_label :service_count, "%d\u2713", ['Count',      '%5d']
  describe_label :registrations, "%d\u2913", ['Registered', '%5d']
  describe_label :expirations,   "%d\u2620", ['Expired',    '%5d']

  def initialize options # :nodoc:
    super

    @ring_server      = nil
    @service_registry = Rinda::TupleSpace.new

    @expirations   = 0
    @registrations = 0
  end

  def description # :nodoc:
    super do |description|
      service_count = @service_registry.read_all([:name, nil, nil, nil]).size

      description[:service_count] = service_count
      description[:registrations] = @registrations
      description[:expirations]   = @expirations
    end
  end

  def run # :nodoc:
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

