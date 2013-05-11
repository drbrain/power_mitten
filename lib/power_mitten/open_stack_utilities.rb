##
# Contains utilities for retrieving data about the environment.

module PowerMitten::OpenStackUtilities

  ##
  # Creates an OpenStack instance for +auth_url+, +tenant+, +username+ and
  # +password

  def new_open_stack auth_url, tenant, username, password
    require 'power_mitten/open_stack'

    PowerMitten::OpenStack.new auth_url, tenant, username, password
  end

  ##
  # Returns the name of this task's VM

  def local_name
    local_server.name
  end

  ##
  # Returns the VM this task is running on

  def local_server
    open_stack.local_server
  end

  ##
  # Returns the number of VCPUs for the VM this task is running on

  def local_vcpus
    local_server.flavor.vcpus
  end

end
