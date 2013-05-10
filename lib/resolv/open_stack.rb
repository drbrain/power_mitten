require 'resolv'
require 'resolv-replace'

##
# A Resolv-compatible name resolver that uses OpenStack to retrieve DNS names.
# This works around not-yet-implemented features in some of the AT&T OpenStack
# datacenters

class Resolv::OpenStack < Resolv::Hosts

  ##
  # The last times names were refreshed from OpenStack

  attr_reader :last_refresh

  ##
  # Creates a new resolver that uses the +open_stack+ instance and refreshes
  # every +refresh_every+ seconds.

  def initialize open_stack, refresh_every = 10
    super open_stack.tenant
    @compute       = compute
    @refresh_every = refresh_every

    @addr2name    = nil
    @name2addr    = nil
    @last_refresh = Time.at 0
  end

  def lazy_initialize # :nodoc:
    @mutex.synchronize do
      return if Time.now < @last_refresh + @refresh_every

      /^search (?<domain>.*)/ =~ File.read('/etc/resolv.conf')

      @name2addr = Hash.new { |h, name| h[name] = [] }
      @addr2name = Hash.new { |h, addr| h[addr] = [] }

      @compute.servers.each do |server|
        name = server.name.downcase.tr '_', '-'
        server.address_list.each do |addr|
          next unless addr =~ /\A10\./

          @addr2name[addr] << name
          @name2addr[name] << addr
          @name2addr["#{name}.#{domain}"] << addr
        end
      end
    end

    self
  end

  ##
  # Yields each address matching +name+

  def each_address name
    super name.downcase
  end

  def inspect # :nodoc:
    "#<%s %s hosts %d addrs %d refresh_every %d last_refresh %p>" % [
      self.class, @filename,
      @name2addr ? @name2addr.size : 0,
      @addr2name ? @addr2name.size : 0,
      @refresh_every, @last_refresh
    ]
  end

end

