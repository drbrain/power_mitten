require 'att/swift'
require 'fog'
require 'optparse'
require 'psych'
require 'resolv/open_stack'
require 'ringy_dingy'
require 'syslog'

class ATT::CloudGauntlet::Node

  extend  ATT::CloudGauntlet::FogUtilities
  include ATT::CloudGauntlet::FogUtilities

  @fog = nil

  attr_reader :swift

  def self.fog
    @fog
  end

  def self.load_configuration file = File.expand_path('~/.gauntlet_control')
    yaml          = File.read file
    configuration = Psych.load yaml
    options       = {}

    %w[
      openstack_api_key
      openstack_auth_url
      openstack_tenant
      openstack_username

      swift_uri
      swift_username
      swift_key
    ].each do |required_key|
      value = configuration[required_key]
      abort "missing #{required_key} in #{file}" unless value

      options[required_key.intern] = value
    end

    options[:swift_uri] = URI options[:swift_uri]

    options
  end

  def self.parse_args argv
    options = {
      configuration: File.expand_path('~/.gauntlet_control'),
      daemon:        false,
      workers:       0,
    }

    OptionParser.accept File do |value|
      raise OptionParser::InvalidArgument, value unless
        File.file?(value) && File.readable?(value)
    end

    op = OptionParser.new do |opt|
      opt.on('--configuration FILE', File) do |file|
        options[:configuration] = file
      end

      opt.on('--daemon') do
        options[:daemon] = true
      end

      opt.on('--localhost') do
        options[:localhost] = true
      end

      opt.on('--once') do
        options[:once] = true
      end

      opt.on('--workers COUNT', Integer) do |count|
        options[:workers] = count
      end
    end

    op.parse argv

    abort op.to_s if options[:configuration].empty?

    if options[:daemon] then
      require 'webrick/server'

      WEBrick::Daemon.start
    end

    options
  end

  def self.prefork options
    require 'servolux'

    workers = options[:workers]
    klass   = self

    pool = Servolux::Prefork.new(max_workers: workers, min_workers: 0) do
      begin
        klass.new(options)._run
      rescue Exception => e
        open '/dev/stderr', 'w' do |io| io.puts e.message end
      end
    end

    pool.start workers

    trap 'INT'  do pool.signal 'KILL' end
    trap 'TERM' do pool.signal 'KILL' end

    Process.waitall
  end

  def self.run argv = ARGV
    options = parse_args argv

    options.merge! load_configuration options[:configuration]

    if options[:workers].zero? then
      @fog = fog_compute(
        options[:openstack_auth_url],
        options[:openstack_tenant],
        options[:openstack_username],
        options[:openstack_api_key])

      options[:workers] =
        ATT::CloudGauntlet::Configuration.workers_for self, local_vcpus
    end

    if options[:workers] < 2 then
      new(options)._run
    else
      prefork options
    end
  end

  def initialize options = {}
    @api_key  = options[:openstack_api_key]
    @auth_url = options[:openstack_auth_url]
    @tenant   = options[:openstack_tenant]
    @username = options[:openstack_username]

    @swift_credentials =
      [options[:swift_uri], options[:swift_username], options[:swift_key]]

    @daemon    = options[:daemon]
    @localhost = options[:localhost]
    @once      = options[:once]

    @fog     = nil
    @control = nil
    @service = nil
    @swift   = nil
    @syslog  =
      if Syslog.opened? then
        Syslog.reopen self.class.name, Syslog::LOG_PID, Syslog::LOG_DAEMON
      else
        Syslog.open   self.class.name, Syslog::LOG_PID, Syslog::LOG_DAEMON
      end

    resolver = Resolv.new [
      Resolv::Hosts.new,
      Resolv::DNS.new,
      Resolv::OpenStack.new(fog)
    ]

    Resolv.send :remove_const, :DefaultResolver
    Resolv.send :const_set, :DefaultResolver, resolver

    notice 'starting'
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

    info "found control hosts #{addresses.join ', '}"

    @control_hosts = addresses
  end

  def error message
    @syslog.err '%s', message
  end

  def find_control
    hosts = control_hosts

    @control = RingyDingy.find :control, hosts

    hosts
  rescue => e
    notice "unable to connect to control at #{hosts.join ', '}: #{e.message} (#{e.class})"
    raise if @once
    sleep 2

    retry
  end

  def fog
    @fog ||= fog_compute @auth_url, @tenant, @username, @api_key
  end

  def get_control
    @control_hosts = nil

    hosts = find_control

    notice "found control at #{@control.__drburi}"

    @service = service local_name, hosts

    @control.register_service self.class, @service, local_name

    @control
  end

  def get_mutex name
    @control.add_mutex name

    RingyDingy.find name, control_hosts
  end

  def get_queue name
    @control.add_queue name

    RingyDingy.find name, control_hosts
  end

  def info message
    @syslog.info '%s', message
  end

  def notice message
    @syslog.notice '%s', message
  end

  def _run
    get_control

    run
  rescue DRb::DRbConnError => e
    raise if @once
    notice "lost connection: #{e.message}"

    @service.stop
    @service = nil

    sleep 10

    retry
  rescue ThreadError
    return # queue empty
  rescue Exception => e
    error "#{e.message} (#{e.class}) - #{e.backtrace.first}"

    raise
  end

  def service name, broadcast, check_every = 10
    service = RingyDingy.new self, name, nil, broadcast
    service.check_every = check_every
    service.run
  end

  def warn message
    super message

    @syslog.warning '%s', message
  end

end

