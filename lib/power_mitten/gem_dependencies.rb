require 'tempfile'

##
# Extracts dependencies from gems in a swift container

class PowerMitten::GemDependencies < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.cpu_multiplier = 8

  def initialize options # :nodoc:
    super options

    @gem_queue              = nil
    @gem_dependencies_queue = nil

    @gems_container = 'gems'
  end

  ##
  # Reads the gem names from the swift container and adds them to the gem
  # queue for processing.
  #--
  # TODO this code is shared amongst a couple tasks and should be moved to a
  # separate service

  def add_gems
    add_gems_mutex = get_mutex 'add_gems'

    add_gems_mutex.synchronize do
      break unless @gem_queue.empty?

      @swift.paginate_objects @gems_container do |object_info|
        @gem_queue.enq object_info['name']
      end
    end
  end

  ##
  # Extracts the dependencies from the spec in +gem+ and adds it to the
  # gem_dependencies queue

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

  ##
  # Attaches to the gem and gem_dependencies queues

  def get_queues
    @gem_queue              = get_queue 'gem'
    @gem_dependencies_queue = get_queue 'gem_dependencies'
  end

  def run # :nodoc:
    super do
      connect_swift

      get_queues

      add_gems

      while gem = @gem_queue.deq(true) do
        extract_dependencies gem
      end
    end
  end

end

