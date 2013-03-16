require 'thread'

class PowerMitten::Control < PowerMitten::Node

  config = PowerMitten::Configuration.new self
  config.add_service PowerMitten::RingServer
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

    @running        = true
    @services       = Hash.new do |h, class_name|
      h[class_name] = {} # class_name => { name: instance }
    end
    @services_mutex = Mutex.new
    @threads        = []
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
    @services_mutex.synchronize do
      begin
        service = RingyDingy.find name, control_hosts

        return false
      rescue RuntimeError # HACK update RingyDingy to have useful exceptions
        options = @options.dup
        options[:name] = name

        start_service PowerMitten::Queue, 1, options

        sleep 10 # HACK wait for Queue to register

        RingyDingy.find name, control_hosts
      end
    end

    return true
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

      service = register instance, name

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

    trap 'INT'  do warn "INT";  DRb.stop_service; stop_services end
    trap 'TERM' do warn "TERM"; DRb.stop_service; stop_services end

    DRb.thread.join

    @threads.each do |thread|
      thread.join
    end
  rescue Interrupt, SystemExit
    raise
  rescue Exception => e
    error "#{e.message} (#{e.class}) - #{e.backtrace.first}"

    raise
  end

  ##
  # Returns the current time.

  def ping
    Time.now
  end

end

