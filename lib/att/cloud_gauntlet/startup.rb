require 'att/cloud_gauntlet/node'
require 'socket'

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

    commands = case name
               when /gauntlet_control/ then %w[ring_server gauntlet_control]
               when /gem_downloader/   then %w[gem_downloader]
               when /checksummer/      then %w[checksummer]
               when /rdocer/           then %w[rdocer]
               end

    notice "registering #{commands.join ', '}"

    commands.each do |command|
      system 'sudo', '/usr/sbin/update-rc.d', '-f', command, 'remove'
      system 'sudo', '/usr/sbin/update-rc.d', '-f', command, 'defaults', '99', '1'
      system 'sudo', "/etc/init.d/#{command}", 'start'

      if $? then
        notice "#{command} started"
      else
        notice "#{command} did not start"
      end
    end
  end

end

