require 'resolv'
require 'resolv-replace'

class Resolv::OpenStack < Resolv::Hosts

  attr_reader :last_refresh

  def initialize compute, refresh_every = 10
    super compute.current_tenant['name']
    @compute       = compute
    @refresh_every = refresh_every

    @addr2name    = nil
    @name2addr    = nil
    @last_refresh = Time.at 0
  end

  def lazy_initialize
    @mutex.synchronize do
      return if Time.now < @last_refresh + @refresh_every

      /^search (?<domain>.*)/ =~ File.read('/etc/resolv.conf')

      @name2addr = Hash.new { |h, name| h[name] = [] }
      @addr2name = Hash.new { |h, addr| h[addr] = [] }

      @compute.servers.each do |vm|
        name = vm.name.downcase.tr '_', '-'
        vm.addresses.values.flatten.each do |entry|
          addr = entry['addr']
          next unless addr =~ /\A10\./

          @addr2name[addr] << name
          @name2addr[name] << addr
          @name2addr["#{name}.#{domain}"] << addr
        end
      end
    end

    self
  end

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

