require 'ringy_dingy/ring_server'

class ATT::CloudGauntlet::RingServer < ATT::CloudGauntlet::Node

  config = ATT::CloudGauntlet::Configuration.new 'ring_server'
  config.services = %w[gauntlet_ring_server]
  config.maximum_workers = 1

  def initialize options
    super

    @ring_server = RingyDingy::RingServer.new Verbose: false, Dameon: false

    @expirations   = nil
    @registrations = nil
  end

  def _run
    DRb.start_service unless DRb.primary_server

    info "listening on #{DRb.uri}"

    @registrations = 
      @ring_server.service_registry.notify 'write', [:name, nil, DRbObject, nil]

    @expirations = 
      @ring_server.service_registry.notify 'delete', [:name, nil, DRbObject, nil]

    Thread.start do
      @registrations.each do |(_, t)|
        notify "registered %p, %p at URI: %s ref: %d" %
          [t[1], t[3], t[2].__drburi, t[2].__drbref]
      end
    end

    Thread.start do
      @expirations.each do |(_, t)|
        notify "expired %p, %p at URI: %s ref: %d" %
          [t[1], t[3], t[2].__drburi, t[2].__drbref]
      end
    end

    Rinda::RingServer.new @ring_server.service_registry

    DRb.thread.join
  end

end

