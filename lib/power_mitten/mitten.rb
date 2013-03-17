##
# The command line interface

class PowerMitten::Mitten

  def self.load_configuration file = File.expand_path('~/.power_mitten')
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
    command = argv.shift

    options = {
      command:       command,
      configuration: File.expand_path('~/.power_mitten'),
      daemon:        false,
      type:          nil,
      workers:       0,
    }

    case command
    when 'console', 'irb' then
      options[:type]    = command.upcase
      options[:workers] = 1
    end

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

      opt.on('--type=TYPE') do |type|
        options[:type] = type
      end

      opt.on('--once') do
        options[:once] = true
      end

      opt.on('--workers COUNT', Integer) do |count|
        options[:workers] = count
      end
    end

    op.parse argv

    abort op.to_s unless command
    abort op.to_s if command.start_with? '-'
    abort op.to_s if options[:configuration].empty?

    case options[:type]
    when 'Control' then
      options[:workers] = 1
    end

    options
  end

  def self.run argv = ARGV
    options = parse_args argv

    options.merge! load_configuration options[:configuration]

    run_command options[:command], options
  end

  def self.run_command command, options
    case command
    when 'console' then
      PowerMitten::Console.new(options).run
    when 'irb' then
      PowerMitten::Irb.new(options).run
    when 'startup' then
      if options[:daemon] then
        require 'webrick/server'

        WEBrick::Daemon.start
      end

      PowerMitten::Startup.new(options).run
    else
      abort "unknown command #{command}"
    end
  end

end

