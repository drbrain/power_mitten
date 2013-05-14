require 'forwardable'

##
# An in-memory mutex service

class PowerMitten::Mutex < PowerMitten::Task

  extend Forwardable

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  describe_label :name,   '%s',  ['Name',   '%s']
  describe_label :locked, '%1s', ['Locked', '%1s']

  def initialize options
    super

    @group = 'Mutex'
    @name  = options[:name]
    @type  = 'Mutex'

    @mutex = Mutex.new
  end

  ##
  # I'm not particularly happy with the extra dispatch here.  I'd rather move
  # this into the TupleSpace directly.

  def_delegators :@mutex, *Mutex.instance_methods(false)

  def description # :nodoc:
    super do |description|
      description[:name]   = @name
      description[:locked] = @mutex.locked? ? "\u2611" : "\u2610"
    end
  end

  def run # :nodoc:
    super do
      @service.thread.join
    end
  end

end

