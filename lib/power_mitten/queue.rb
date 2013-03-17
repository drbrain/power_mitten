class PowerMitten::Queue < PowerMitten::Node

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  attr_reader :name
  attr_reader :queue

  def initialize options
    super

    @name  = options[:name]
    @queue = Queue.new
    @type = 'Queue'
  end

  def description # :nodoc:
    _, name = @name.split '-', 2

    "#{name}, #{super}"
  end

  def run
    service = nil

    super do
      service ||= register @queue, @name

      service.thread.join
    end
  end

end

