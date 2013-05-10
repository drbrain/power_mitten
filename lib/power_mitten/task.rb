require 'optparse'
require 'psych'
require 'resolv/open_stack'
require 'ringy_dingy'
require 'syslog'

##
# A task allows an application builder to create a service that communicates
# with other tasks.  The task provides API to register itself and connect to
# other services.

class PowerMitten::Task

  extend  PowerMitten::OpenStackUtilities
  include PowerMitten::OpenStackUtilities
  include DRb::DRbUndumped

  @open_stack = nil

  @label_orders = Hash.new { |h, klass| h[klass] = [] }
  @labels       = Hash.new { |h, klass| h[klass] = {} }

  class << self
    attr_reader :label_orders # :nodoc:
    attr_reader :labels # :nodoc:
  end

  attr_reader :swift

  ##
  # Threads wrapping subprocesses managed by this task.

  attr_reader :threads # :nodoc:

  def self.open_stack
    @open_stack
  end

  ##
  # Returns a sprintf format string for +field+ when used to display an
  # aggregate entry.

  def self.aggregate_description field
    label_descriptions[field].first
  end

  ##
  # Returns a field, column label and sprintf format string for the
  # labels of this task in label order.

  def self.column_descriptions
    label_order.map do |field|
      [field].concat label_descriptions[field].last
    end
  end

  ##
  # Describes the +field+ in the Task's #description with the given
  # +aggregate+ and +column+ formats.
  #
  # These are the default labels for every task:
  #
  #   describe_label :RSS,      '%7d RSS', ['RSS KB',   '%8d', 8]
  #   describe_label :hostname, '%s',      ['hostname', '%s']
  #   describe_label :pid,      'pid %5d', ['PID',      '%5d', 5]
  #
  # The +field+ is returned by #description and its order of display is set
  # based on when it was defined.  The +column+ description includes the
  # column name, the sprintf format string for the column and the field width.
  # If the column size is omitted the column will be automatically sized based
  # on the largest column (or column title).

  def self.describe_label field, aggregate, column
    column << 0 if column.size == 2

    PowerMitten::Task.labels[self][field] = [aggregate, column]
    PowerMitten::Task.label_orders[self] << field
  end

  ##
  # Descriptions for labels from the current class.  Use aggregate_description
  # and column_descriptions instead.

  def self.label_descriptions # :nodoc:
    PowerMitten::Task.labels[PowerMitten::Task].merge \
      PowerMitten::Task.labels[self]
  end

  ##
  # The order labels are displayed on the console.  Label order is defined by
  # the order of describe_label calls.

  def self.label_order
    order = PowerMitten::Task.label_orders[PowerMitten::Task]
    order += PowerMitten::Task.label_orders[self] unless
      PowerMitten::Task == self
    order
  end

  describe_label :pid,      'pid %5d', ['PID',      '%5d', 5]
  describe_label :hostname, '%s',      ['Hostname', '%s']
  describe_label :RSS,      '%7d RSS', ['RSS KB',   '%8d', 8]

  ##
  # The class name minus any namespacing is used for the short name

  def self.short_name
    name.split('::').last
  end

  ##
  # Creates a new Task.  This is typically invoked via super.  +options+ uses
  # the following entries:
  #
  # :daemon::
  #   If true, run as a daemon
  # :localhost::
  #   If true, do not attempt to self-configure via OpenStack.  The type
  #   option must be set manually when running in localhost mode.
  # :once::
  #   If true, abort upon the first exception
  # :type::
  #   When run in localhost mode, sets the type of task to create.
  #
  # :openstack_api_key::
  #   The API key or password used to log in
  # :openstack_auth_url::
  #   The OpenStack authentication URL
  # :openstack_tenant::
  #   The tenant to log in to
  # :openstack_username::
  #   The username to log in as
  #
  # :swift_uri::
  #   The URI to swift
  # :swift_username::
  #   The username to log in as
  # :swift_key::
  #   The password used to log in

  def initialize options = {}
    @options  = options

    @api_key  = options[:openstack_api_key]
    @auth_url = options[:openstack_auth_url]
    @tenant   = options[:openstack_tenant]
    @username = options[:openstack_username]

    @swift_credentials =
      [options[:swift_uri], options[:swift_username], options[:swift_key]]

    @daemon    = options[:daemon]
    @localhost = options[:localhost]
    @once      = options[:once]
    @type      = options[:type]

    @open_stack    = nil
    @control       = nil
    @control_hosts = nil
    @ring_lookup   = nil
    @running       = true
    @service       = nil
    @swift         = nil
    @syslog        =
      if Syslog.opened? then
        Syslog.reopen short_name, Syslog::LOG_PID, Syslog::LOG_DAEMON
      else
        Syslog.open   short_name, Syslog::LOG_PID, Syslog::LOG_DAEMON
      end
    @threads       = []

    resolvers = [
      Resolv::Hosts.new,
      Resolv::DNS.new,
    ]

    resolvers.push Resolv::OpenStack.new(open_stack) unless @localhost
    resolvers.unshift Resolv::MDNS.new if Resolv.const_defined? :MDNS

    resolver = Resolv.new resolvers

    Resolv.send :remove_const, :DefaultResolver
    Resolv.send :const_set, :DefaultResolver, resolver

    notice "starting #{self.class}"
  end

  ##
  # Connects to swift using ATT::Swift

  def connect_swift
    return @swift if @swift

    require 'att/swift'

    @swift = ATT::Swift.new(*@swift_credentials)

    notice 'connected to swift'

    @swift
  end

  ##
  # Discovers the control hosts on the local network
  #
  # This method is a workaround for lack of broadcast UDP or multicast support
  # in the AT&T OpenStack data centers.

  def control_hosts
    return @control_hosts if @control_hosts
    return @control_hosts = %w[127.0.0.1] if @localhost

    control_hosts = open_stack.servers.select do |vm|
      vm.name =~ /\AControl/
    end.uniq

    return [] unless control_hosts

    addresses = control_hosts.map do |vm|
      vm.addresses.values.flatten.map do |address|
        next unless address['addr'] =~ /\A10\./

        address['addr']
      end
    end.flatten.compact.uniq

    raise "no control hosts found" if addresses.empty?

    notice "found control hosts #{addresses.join ', '}"

    @control_hosts = addresses
  end

  ##
  # Sends syslog a debug +message+

  def debug message
    @syslog.debug '%s', message
  end

  ##
  # Returns a hash that describes this task for the Console.  A task may
  # override this to return additional information, but be sure to also
  # describe the labels:
  #
  #   describe_label :checked, "%d\u2713", ['checked', '%5d']
  #
  #   def description # :nodoc:
  #     super do |description|
  #       description[:checked] = @checked
  #     end
  #   end

  def description
    rss = nil

    description = {
      klass:    self.class,
      hostname: hostname,
      pid:      $$,
    }

    description[:RSS] = rss if rss = resident_set_size

    yield description if block_given?

    description
  end

  ##
  # Sends syslog an error +message+

  def error message
    @syslog.err '%s', message
  end

  ##
  # Sends syslog a fatal +message+

  def fatal message
    @syslog.alert '%s', message
  end

  ##
  # Finds the control service and assigns it to @control

  def find_control
    hosts = control_hosts

    @ring_lookup = RingyDingy::Lookup.new hosts

    @control = @ring_lookup.find 'Mitten-control'

    hosts
  rescue => e
    notice "unable to connect to control at #{hosts.join ', '}: #{e.message} (#{e.class})"
    raise if @once

    @control_hosts = nil
    sleep 2

    retry
  end

  ##
  # Creates a PowerMitten::OpenStack instance using the OpenStack credentials

  def open_stack
    @open_stack ||= new_open_stack @auth_url, @tenant, @username, @api_key
  end

  ##
  # Forks a process to run the class +service+.  The +options+ are sent to the
  # service's \#initialize.  Returns the pid of the forked process.

  def fork_child service, options
    pid = fork do
      Process.setsid

      trap 'INT',  'DEFAULT'
      trap 'TERM', 'DEFAULT'

      $PROGRAM_NAME = "mitten #{service.short_name}"

      # The thread was killed but the protocol wasn't closed, so do it
      # manually.  This should be fixed in DRb.
      begin
        server = DRb.current_server
        server.instance_variable_get(:@protocol).close
      rescue DRb::DRbServerNotFound
      end

      DRb.stop_service
      DRb.start_service

      service.new(options).run
    end

    notice "forked #{service.name} at #{pid}"

    pid
  end

  ##
  # Gets the control service and registers with it, replacing the previous
  # control service.

  def get_control
    @control_hosts = nil

    find_control

    notice "found control at #{@control.__drburi}"

    @service = register self, "Mitten-#{local_name}"

    @control
  end

  ##
  # Finds or creates a drip service.

  def get_drip
    drip = @control.add_drip

    notice "found drip at #{drip.__drburi}"

    drip
  end

  ##
  # Finds or creates a Mutex service with +name+.

  def get_mutex name
    mutex_name = "Mutex-#{name}"

    mutex = @control.add_mutex mutex_name

    notice "found #{mutex_name} at #{mutex.__drburi}"

    mutex
  end

  ##
  # Finds or creates a Queue service with +name+.

  def get_queue name
    queue_name = "Queue-#{name}"

    queue = @control.add_queue queue_name

    notice "found #{queue_name} at #{queue.__drburi}"

    queue
  end

  ##
  # Finds or creates a PowerMitten::Statistic service with +name+

  def get_statistic name
    statistic_name = "Statistic-#{name}"

    notice "looking up #{statistic_name}"

    statistic = @ring_lookup.find name
  rescue RuntimeError
    statistic = @control.add_statistic statistic_name
  ensure
    if statistic then
      notice "found #{statistic_name} at #{statistic.__drburi}"
    else
      error "could not find or create #{statistic_name}"
    end

    statistic
  end

  ##
  # The DNS name of where this task is running

  def hostname
    Socket.gethostname.split('.', 2).first
  end

  ##
  # Sends syslog an info +message+

  def info message
    @syslog.info '%s', message
  end

  ##
  # Returns the name of this task which may have been overridden by the
  # +--type+ command-line option.

  def local_name
    @type || super
  end

  ##
  # Sends syslog a notice +message+

  def notice message
    @syslog.notice '%s', message
  end

  ##
  # The process ID of this task

  def pid
    $$
  end

  ##
  # RSS in kilobytes

  def resident_set_size
    case RUBY_PLATFORM
    when /\Ax86_64-darwin12\./ then
      require 'power_mitten/mach'

      PowerMitten::Mach.resident_set_size / 1024
    end
  end

  ##
  # Starts running this task.  A typical task will super to this
  # implementation:
  #
  #   def run
  #     super do
  #       get_resources
  #
  #       do_work
  #     end
  #   end
  #
  # #run takes care of attaching to the control node and restarting the task
  # if a DRb exception occurred.

  def run
    get_control

    yield
  rescue DRb::DRbConnError => e
    raise if @once
    notice "lost connection: #{e.message}"

    @service.stop
    @service = nil

    sleep 10

    retry
  rescue ThreadError
    return # queue empty
  rescue SignalException, SystemExit
    raise
  rescue Exception => e
    error "#{e.message} (#{e.class}) - #{e.backtrace.first}"

    raise
  end

  ##
  # Registers +object+ as +name+.
  #
  # Registration allows other services to discover and use the API presented
  # by the object.

  def register object, name
    service = RingyDingy.new object, name, nil, @ring_lookup
    service.check_every = 60
    service.run :first_register
  end

  ##
  # Returns a list of all registered services.

  def services
    services = RingyDingy::RingServer.list_services

    services.values.flatten 1
  end

  ##
  # The class name not including any namespacing

  def short_name
    self.class.short_name
  end

  ##
  # Starts the +service+ (which is a class) in a new process.  +workers+
  # processes will be created.  +options+ is sent to the \#initialize method
  # of the +service+.
  #
  # Worker children will be automatically restarted unless they exit
  # successfully or are killed with a TERM signal.
  #
  # Worker children are added to a list of threads and can be shut down via
  # stop_services.

  def start_service service, workers, options = @options
    ok_signals = Signal.list.values_at 'INT', 'TERM'

    workers.times.map do
      thread = Thread.new do
        while @running do
          pid = fork_child service, options

          Thread.current[:pid] = pid

          _, status = Process.wait2 pid

          notice "service #{service} #{status}"

          break if status.success?
          break if ok_signals.include?(status.termsig)
        end
      end

      @threads << thread
    end
  end

  ##
  # Stops services started by start_service.  Each child is sent a TERM
  # signal.
  #
  # If your task starts children with it should call stop_services via at
  # least INT and TERM signal handlers.

  def stop_services
    @running = false

    @threads.each do |thread|
      pid = thread[:pid]

      next unless pid

      notice "shutting down #{pid}"

      begin
        Process.kill 'TERM', pid
      rescue Errno::ESRCH
        notice "process #{pid} not found"
      end
    end
  end

  ##
  # Sends syslog a warning +message+

  def warn message
    super message

    @syslog.warning '%s', message
  end

end

