require 'digest/md5'
require 'digest/sha2'

class PowerMitten::GemChecksummer < PowerMitten::Node

  config = PowerMitten::Configuration.new self
  config.cpu_multiplier = 8

  attr_reader :gem_queue
  attr_reader :gem_checksum_queue

  def initialize options
    super options

    @gem_queue    = nil
    @md5_queue    = nil
    @sha512_queue = nil

    @gems_container = 'gems'
  end

  def add_gems
    add_gems_mutex = get_mutex 'add_gems'

    add_gems_mutex.synchronize do
      break unless @gem_queue.empty?

      @swift.paginate_objects @gems_container do |object_info|
        @gem_queue.enq object_info['name']
      end
    end
  end

  def checksum gem
    md5    = Digest::MD5.new
    sha512 = Digest::SHA512.new

    info "checksumming #{gem} from #{@gems_container}"

    @swift.read_object @gems_container, gem do |res|
      res.read_body do |chunk|
        md5 << chunk
        sha512 << chunk
      end

      raise "checksum mismatch for #{@gems_container}/#{gem}" unless
        res['ETag'] == md5.hexdigest
    end

    @md5_queue << [gem, md5.hexdigest]
    @sha512_queue << [gem, sha512.hexdigest]
  end

  def get_queues
    @gem_queue    = get_queue 'gem'
    @md5_queue    = get_queue 'md5'
    @sha512_queue = get_queue 'sha512'
  end

  def run
    super do
      swift = connect_swift

      swift.create_container @gems_container

      get_queues

      add_gems

      while gem = @gem_queue.deq(true) do
        checksum gem
      end
    end
  end

end

