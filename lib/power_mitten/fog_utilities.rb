##
# Contains utilities for retrieving data about the environment using fog.

module PowerMitten::FogUtilities

  def self.extended mod # :nodoc:
    super

    mod.instance_variable_set :@local_ip, nil
  end

  def self.included mod # :nodoc:
    super

    mod.instance_variable_set :@local_ip, nil
  end

  ##
  # Creates a fog compute instance for +auth_url+, +tenant+, +username+ and
  # +api_key+.

  def fog_compute auth_url, tenant, username, api_key
    require 'fog/openstack'

    Fog::Compute.new \
      provider: :openstack,
      openstack_api_key:  api_key,
      openstack_auth_url: auth_url,
      openstack_tenant:   tenant,
      openstack_username: username
  end

  ##
  # From http://coderrr.wordpress.com/2008/05/28/get-your-local-ip-address/

  def local_ip
    @local_ip ||= UDPSocket.open do |s|
      s.connect '192.0.2.1', 1
      s.addr.last
    end
  end

  ##
  # Returns the name of this task's VM

  def local_name
    local_vm.name
  end

  ##
  # Returns the VM this task is running on

  def local_vm
    local_vm = fog.servers.find do |vm|
      addresses = vm.addresses.values.flatten

      next unless addresses

      addresses.any? do |address|
        address['addr'] == local_ip
      end
    end

    return local_vm if local_vm

    raise "unable to find vm for #{local_ip}"
  end

  ##
  # Returns the number of VCPUs for the VM this task is running on

  def local_vcpus
    flavor_id = local_vm.flavor['id']

    flavor = fog.flavors.find { |f| f.id == flavor_id }

    flavor.vcpus
  end

end

