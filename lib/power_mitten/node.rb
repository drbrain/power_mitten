require 'att/swift'
require 'fog'
require 'optparse'
require 'psych'
require 'resolv/open_stack'
require 'ringy_dingy'
require 'syslog'

class PowerMitten::Node

  extend  PowerMitten::FogUtilities
  include PowerMitten::FogUtilities

  @fog = nil

  @label_orders = {}
  @labels = Hash.new { |h, klass| h[klass] = {} }

  class << self
    attr_reader :label_orders # :nodoc:
    attr_reader :labels # :nodoc:
  end

  attr_reader :swift
  attr_accessor :level # :nodoc:

  def self.fog
    @fog
  end

  ##
  # Returns a sprintf format string for +field+ when used to display an
  # aggregate entry.

  def self.aggregate_description field
    label_descriptions[field].first
  end

  ##
  # Returns a field, column label and sprintf format string for the
  # labels of this node in label order.

  def self.column_descriptions
    label_order.map do |field|
      [field].concat label_descriptions[field].last
    end
  end

  ##
  # Describes the +field+ in the Node's #description with the given
  # +aggregate+ and +column+ formats.
  #
  # These are the default labels for every node:
  #
  #   describe_label :RSS,      '%7d RSS', ['RSS KB',   '%8d', 8]
  #   describe_label :hostname, '%s',      ['hostname', '%s']
  #   describe_label :pid,      'pid %5d', ['PID',      '%5d', 5]
  #
  # The +field+ is returned by #description and its order of display is set
  # by ::label_order=.  The +column+ description includes the column name, the
  # sprintf format string for the column and the field width.  If the column
  # size is omitted the column will be automatically sized based on the
  # largest column (or column title).

  def self.describe_label field, aggregate, column
    column << 0 if column.size == 2

    PowerMitten::Node.labels[self][field] = [aggregate, column]
  end

  ##
  # Descriptions for labels from the current class.  Use aggregate_description
  # and column_descriptions instead.

  def self.label_descriptions # :nodoc:
    PowerMitten::Node.labels[PowerMitten::Node].merge \
      PowerMitten::Node.labels[self]
  end

  ##
  # The order labels are displayed on the console.  Define with label_order=

  def self.label_order
    PowerMitten::Node.label_orders[self] ||
      PowerMitten::Node.label_orders[PowerMitten::Node]
  end

  ##
  # Sets the order labels are displayed on the console.

  def self.label_order= order
    PowerMitten::Node.label_orders[self] = order
  end

  self.label_order = [:pid, :hostname, :RSS]

  describe_label :RSS,      '%7d RSS', ['RSS KB',   '%8d', 8]
  describe_label :hostname, '%s',      ['Hostname', '%s']
  describe_label :pid,      'pid %5d', ['PID',      '%5d', 5]

  def self.short_name
    name.split('::').last
  end

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

    @fog         = nil
    @control     = nil
    @level       = nil
    @ring_finger = nil
    @service     = nil
    @swift       = nil
    @syslog      =
      if Syslog.opened? then
        Syslog.reopen short_name, Syslog::LOG_PID, Syslog::LOG_DAEMON
      else
        Syslog.open   short_name, Syslog::LOG_PID, Syslog::LOG_DAEMON
      end

    resolvers = [
      Resolv::Hosts.new,
      Resolv::DNS.new,
    ]

    resolvers.push Resolv::OpenStack.new(fog) unless @localhost
    resolvers.unshift Resolv::MDNS.new if Resolv.const_defined? :MDNS

    resolver = Resolv.new resolvers

    Resolv.send :remove_const, :DefaultResolver
    Resolv.send :const_set, :DefaultResolver, resolver

    notice "starting #{self.class}"
  end

  def connect_swift
    return @swift if @swift

    @swift = ATT::Swift.new(*@swift_credentials)

    notice 'connected to swift'

    @swift
  end

  def control_hosts
    return %w[127.0.0.1] if @localhost

    return @control_hosts if @control_hosts

    control_hosts = fog.servers.select do |vm|
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

    info "found control hosts #{addresses.join ', '}"

    @control_hosts = addresses
  end

  def debug message
    @syslog.debug '%s', message
  end

  ##
  # Returns a hash that describes this node for the Console.  A node may
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

  def error message
    @syslog.err '%s', message
  end

  def fatal message
    @syslog.alert '%s', message
  end

  def find_control
    hosts = control_hosts

    @control = RingyDingy.find 'Mitten-control', hosts

    hosts
  rescue => e
    notice "unable to connect to control at #{hosts.join ', '}: #{e.message} (#{e.class})"
    raise if @once

    @control_hosts = nil
    sleep 2

    retry
  end

  def fog
    @fog ||= fog_compute @auth_url, @tenant, @username, @api_key
  end

  def fork_child service, workers, options
    pid = fork do
      Process.setsid

      trap 'INT',  'DEFAULT'
      trap 'TERM', 'DEFAULT'

      $PROGRAM_NAME = "mitten #{service.short_name}"
      DRb.stop_service
      DRb.start_service

      service.new(options).run
    end

    notice "forked #{service.name} at #{pid}"

    pid
  end

  def get_control
    @control_hosts = nil

    hosts = find_control

    notice "found control at #{@control.__drburi}"

    @ring_finger = Rinda::RingFinger.new control_hosts
    RingyDingy::RingServer.ring_finger = @ring_finger

    @service = service local_name, hosts

    @control
  end

  def get_mutex name
    mutex_name = "Mutex-#{name}"
    @control.add_mutex mutex_name

    RingyDingy.find mutex_name, control_hosts
  end

  def get_queue name
    queue_name = "Queue-#{name}"
    @control.add_queue queue_name

    RingyDingy.find queue_name, control_hosts
  end

  ##
  # The DNS name of where this node is running

  def hostname
    Socket.gethostname.split('.', 2).first
  end

  def info message
    @syslog.info '%s', message
  end

  ##
  # Returns the name of this node which may have been overridden by the
  # +--type+ command-line option.

  def local_name
    @type || super
  end

  def notice message
    @syslog.notice '%s', message
  end

  ##
  # The process ID of this node

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

  def register object, name
    service = RingyDingy.new object, name, nil, control_hosts
    service.check_every = 10
    service.run :first_register
  end

  def service name, broadcast, check_every = 1
    service = RingyDingy.new self, "Mitten-#{name}", nil, broadcast
    service.check_every = check_every
    service.run :first_register
  end

  def services
    services = RingyDingy::RingServer.list_services

    services.values.flatten 1
  end

  def short_name
    self.class.short_name
  end

  def start_service service, workers, options = @options
    ok_signals = Signal.list.values_at 'TERM', 'INT'

    workers.times.map do
      Thread.new do
        while @running do
          pid = fork_child service, workers, options

          Thread.current[:pid] = pid

          _, status = Process.wait2 pid

          notice "service #{service} #{status}"

          break if status.success?
          break if ok_signals.include?(status.termsig)
        end
      end
    end
  end

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

  def warn message
    super message

    @syslog.warning '%s', message
  end

end

