require 'forwardable'

##
# An in-memory queue service

class PowerMitten::Queue < PowerMitten::Task

  extend Forwardable

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  describe_label :name,       '%s',   ['Name',    '%s']
  describe_label :size,       '%7d',  ['Items',   '%7d', 7]
  describe_label :delta,      '%4d',  ['Delta',   '%4d', 4]
  describe_label :per_second, '%6g',  ['Items/s', '%7g', 7]

  ##
  # Creates a new queue using the +:name+ option in +options+

  def initialize options
    super

    @group = 'Queue'
    @name  = options[:name]
    @type  = 'Queue'

    @queue            = Queue.new
    @last_description = Time.at 0
    @last_size        = 0
  end

  ##
  # I'm not particularly happy with the extra dispatch here

  def_delegators :@queue, *Queue.instance_methods(false)

  def description # :nodoc:
    size = @queue.size
    now  = Time.now

    delta      = size - @last_size
    per_second = delta / (now - @last_description)

    @last_description = now
    @last_size        = size

    super do |description|
      description[:name]       = @name
      description[:size]       = size
      description[:delta]      = delta
      description[:per_second] = per_second
    end
  end

  def run # :nodoc:
    super do
      @service.thread.join
    end
  end

end

