require 'irb'
require 'pp'

class ATT::CloudGauntlet::Irb < ATT::CloudGauntlet::Node

  config = ATT::CloudGauntlet::Configuration.new self
  config.maximum_workers = 1

  def initialize options = {}
    super

    @type = 'Irb' if @localhost
  end

  def run
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

