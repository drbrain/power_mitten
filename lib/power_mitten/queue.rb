##
# An in-memory queue service

class PowerMitten::Queue < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  describe_label :name, '%s', ['Name', '%s']

  ##
  # Creates a new queue using the +:name+ option in +options+

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

  def run # :nodoc:
    service = nil

    super do
      service ||= register @queue, @name

      service.thread.join
    end
  end

end

