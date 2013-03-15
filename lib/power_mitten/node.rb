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

  attr_reader :swift
  attr_accessor :level # :nodoc:

  def self.fog
    @fog
  end

  def self.short_name
    name.split('::').last
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
    @type      = options[:type]

    @fog     = nil
    @control = nil
    @level   = nil
    @service = nil
    @swift   = nil
    @syslog  =
      if Syslog.opened? then
        Syslog.reopen self.class.short_name, Syslog::LOG_PID, Syslog::LOG_DAEMON
      else
        Syslog.open   self.class.short_name, Syslog::LOG_PID, Syslog::LOG_DAEMON
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

  def error message
    @syslog.err '%s', message
  end

  def fatal message
    @syslog.alert '%s', message
  end

  def find_control
    hosts = control_hosts

    @control = RingyDingy.find :control, hosts

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

  ##
  # Returns the name of this node which may have been overridden by the
  # +--type+ command-line option.

  def local_name
    @type || super
  end

  def notice message
    @syslog.notice '%s', message
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

  def service name, broadcast, check_every = 10
    service = RingyDingy.new self, name, nil, broadcast
    service.check_every = check_every
    service.run :first_register
  end

  def warn message
    super message

    @syslog.warning '%s', message
  end

end

