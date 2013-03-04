class ATT::CloudGauntlet::Startup < ATT::CloudGauntlet::Node

  def self.run argv = ARGV
    options = parse_args argv

    options.merge! load_configuration options[:configuration]

    startup = new options

    startup.run
  end

  def initialize options = {}
    super

    @local_ip = nil
  end

  def run
    name = local_name

    notice "this is a #{name} node"

    services = ATT::CloudGauntlet::Configuration.services_for name

    notice "registering #{services.join ', '}"

    services.each do |service|
      system 'sudo', '/usr/sbin/update-rc.d', '-f', service, 'remove'
      system 'sudo', '/usr/sbin/update-rc.d', '-f', service, 'defaults', '99', '1'
      system 'sudo', "/etc/init.d/#{service}", 'start'

      if $? then
        notice "#{service} started"
      else
        notice "#{service} did not start"
      end
    end
  end

end

