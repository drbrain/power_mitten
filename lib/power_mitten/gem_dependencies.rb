require 'tempfile'

class PowerMitten::GemDependencies < PowerMitten::Node

  config = PowerMitten::Configuration.new self
  config.cpu_multiplier = 8

  attr_reader :gem_queue
  attr_reader :gem_dependencies_queue

  def initialize options
    super options

    @gem_queue              = nil
    @gem_dependencies_queue = nil

    @gems_container = 'gems'
  end

  def add_gems
    add_gems_mutex = get_mutex :add_gems

    add_gems_mutex.synchronize do
      break unless @gem_queue.empty?

      @swift.paginate_objects @gems_container do |object_info|
        @gem_queue.enq object_info['name']
      end
    end
  end

  def extract_dependencies gem
    Tempfile.open gem do |io|
      @swift.read_object @gems_container, gem do |res|
        res.read_body do |chunk|
          io.write chunk
        end
      end

      io.flush

      package = Gem::Package.new io.path

      spec = package.spec

      @gem_dependencies_queue.enq [spec.full_name, spec.dependencies]
    end
  rescue Gem::Exception => e
    @gem_dependencies_queue.enq [
      spec.full_name, :failed, e.class.name, e.message
    ]
  end

  def get_queues
    @gem_queue              = get_queue :gem_queue
    @gem_dependencies_queue = get_queue :gem_dependencies_queue
  end

  def run
    super do
      swift = connect_swift

      get_queues

      add_gems

      while gem = @gem_queue.deq(true) do
        extract_dependencies gem
      end
    end
  end

end

