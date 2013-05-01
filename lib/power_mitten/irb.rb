require 'irb'
require 'pp'

class PowerMitten::Irb < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  def initialize options = {}
    super

    @type = 'Irb' if @localhost
  end

  def run
    puts <<-MESSAGE
Welcome to mitten irb!

You are in a PowerMitten::Irb instance.  If the control task shuts down the
session will re-connect to the next control task that appears.

You will find the following instance variables and methods useful.  You can
find the referenced documentation using `ri`:

  get_*:
    Retrieves the given resource.  See the PowerMitten::Task for details on
    the available resources.

  @control:
    The PowerMitten::Control task, you can ask it to create services on your
    behalf if the get_* methods are insufficient.

  @ring_lookup:
    A RingyDingy::Lookup, you can ask it for registered services.

    MESSAGE

    super do
      ARGV.clear
      IRB.setup nil
      IRB.conf[:MAIN_CONTEXT] = IRB::Irb.new.context
      IRB.conf[:PROMPT_MODE] = :SIMPLE
      require 'irb/ext/multi-irb'
      IRB.irb nil, self
    end
  end

end

