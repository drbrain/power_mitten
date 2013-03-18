class PowerMitten::Queue < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  self.label_order = [:name] + PowerMitten::Task.label_order

  describe_label :name, '%s', ['Name', '%s']

  attr_reader :name
  attr_reader :queue

  def initialize options
    super

    @name  = options[:name]
    @queue = Queue.new
    @type = 'Queue'
  end

  def description # :nodoc:
    super do |description|
      _, name = @name.split '-', 2

      description[:name] = name
    end
  end

  def run
    service = nil

    super do
      service ||= register @queue, @name

      service.thread.join
    end
  end

end

