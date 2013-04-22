require 'thread'

class PowerMitten::Control < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.add_service PowerMitten::RingServer
  config.maximum_workers = 1

  self.label_order = PowerMitten::Task.label_order + [:children]

  describe_label :children, '%2d children', ['Children', '%2d']

  attr_reader :services
  attr_reader :threads

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
  # Adds a Drip to the control task.

  def add_drip
    @services_mutex.synchronize do
      begin
        service = RingyDingy.find 'drip', control_hosts

        return service
      rescue RuntimeError # HACK update RingyDingy to have useful exceptions
        options = @options.dup

        start_service PowerMitten::Drip, 1, options

        return RingyDingy::Lookup.new(control_hosts).wait_for 'drip'
      end
    end
  end

  ##
  # Adds a new Mutex with +name+ to the control task.  Returns +true+ if the
  # Mutex was created, +false+ if it already exists.

  def add_mutex name
    add_service Mutex, name
  end

  ##
  # Adds a new Queue with +name+ to the control task.  Returns +true+ if the
  # Queue was created, +false+ if it already exists.

  def add_queue name
    @services_mutex.synchronize do
      begin
        RingyDingy.find name, control_hosts
      rescue RuntimeError # HACK update RingyDingy to have useful exceptions
        options = @options.dup
        options[:name] = name

        start_service PowerMitten::Queue, 1, options

        return RingyDingy::Lookup.new(control_hosts).wait_for name
      end
    end
  end

  ##
  # Returns the previously registered service of type +klass+ with the given
  # +name+.
  #
  # If no service was registered, creates a new item by calling +new+ on the
  # given +klass+ and returning the new instance.  When creating a new
  # service the return will be delayed until the service is registered.

  def add_service klass, name
    class_name = klass.name

    instance = nil

    @services_mutex.synchronize do
      instance = @services[class_name][name]

      return instance if instance

      instance = klass.new

      service = register instance, name

      @services[class_name][name] = service
    end

    notice "added #{klass.name} #{name}"

    instance
  end

  def description # :nodoc:
    super do |description|
      description[:children] = @threads.size
    end
  end

  ##
  # Registers +service+ with +name+ to the control task.

  def register_service klass, service, name
    @services_mutex.synchronize do
      @services[klass.name][name] = service
    end

    info "registered remote service #{klass.name} #{name} from #{service.__drburi}"
  end

  def run
    control_service = service 'control', control_hosts, 1

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

