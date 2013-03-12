require 'thread'

class ATT::CloudGauntlet::Control < ATT::CloudGauntlet::Node

  config = ATT::CloudGauntlet::Configuration.new self
  config.services = %w[gauntlet_ring_server gauntlet_control]
  config.maximum_workers = 1

  attr_reader :services

  def self.run argv = ARGV
    options = parse_args argv

    options.merge! load_configuration options[:configuration]

    control = new options

    control.run
  end

  def initialize options = {}
    super

    @services = Hash.new do |h, class_name|
      h[class_name] = {} # class_name => { name: instance }
    end
    @services_mutex = Mutex.new
  end

  ##
  # Adds a new Mutex with +name+ to the control node.  Returns +true+ if the
  # Mutex was created, +false+ if it already exists.

  def add_mutex name
    add_service Mutex, name
  end

  ##
  # Adds a new Queue with +name+ to the control node.  Returns +true+ if the
  # Queue was created, +false+ if it already exists.

  def add_queue name
    add_service Queue, name
  end

  ##
  # Adds service +klass+ with +name+ to the control node.  Returns +true+ if
  # a named instance of +klass+ was added, +false+ if it already exists.

  def add_service klass, name
    class_name = klass.name

    @services_mutex.synchronize do
      instance = @services[class_name][name]

      return false if instance

      instance = klass.new

      service = RingyDingy.new instance, name
      service.check_every = 2
      service.run :first_register

      @services[class_name][name] = service

      true
    end

    info "added #{klass.name} #{name}"
  end

  ##
  # Registers +service+ with +name+ to the control node.

  def register_service klass, service, name
    @services_mutex.synchronize do
      @services[klass.name][name] = service
    end

    info "registered remote service #{klass.name} #{name} from #{service.__drburi}"
  end

  def run
    control_service = service :control, control_hosts, 1

    info "control registered at #{control_service.ring_server.__drburi}"

    DRb.thread.join
  rescue
    error "#{$!.message} (#{$!.class})"
  end

  ##
  # Returns the current time.

  def ping
    Time.now
  end

end

