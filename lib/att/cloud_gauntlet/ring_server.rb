require 'ringy_dingy/ring_server'

class ATT::CloudGauntlet::RingServer < ATT::CloudGauntlet::Node

  config = ATT::CloudGauntlet::Configuration.new self
  config.maximum_workers = 1

  def initialize options
    super

    @ring_server = RingyDingy::RingServer.new Verbose: false, Dameon: false

    @expirations   = nil
    @registrations = nil
  end

  def run
    DRb.start_service unless DRb.primary_server

    notice "listening on #{DRb.uri}"

    @registrations =
      @ring_server.service_registry.notify 'write', [:name, nil, DRbObject, nil]

    @expirations =
      @ring_server.service_registry.notify 'delete', [:name, nil, DRbObject, nil]

    Thread.start do
      @registrations.each do |(_, t)|
        notice "registered %p, %p at URI: %s ref: %d" %
          [t[1], t[3], t[2].__drburi, t[2].__drbref]
      end
    end

    Thread.start do
      @expirations.each do |(_, t)|
        notice "expired %p, %p at URI: %s ref: %d" %
          [t[1], t[3], t[2].__drburi, t[2].__drbref]
      end
    end

    Rinda::RingServer.new @ring_server.service_registry

    DRb.thread.join
  end

end

