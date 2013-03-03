require 'att/cloud_gauntlet/node'
require 'irb'
require 'pp'

class ATT::CloudGauntlet::Irb < ATT::CloudGauntlet::Node

  def run
    ARGV.clear
    IRB.setup nil
    IRB.conf[:MAIN_CONTEXT] = IRB::Irb.new.context
    IRB.conf[:PROMPT_MODE] = :SIMPLE
    require 'irb/ext/multi-irb'
    IRB.irb nil, self
  end

end

