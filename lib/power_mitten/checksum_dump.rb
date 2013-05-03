##
# Dumps the queues from the GemChecksummer task to a file
#--
# TODO: This task should be run only once and exit, but no mechanism exists to
# tell power_mitten that.

class PowerMitten::ChecksumDump < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  def initialize options # :nodoc:
    super options

    @gem_queue    = nil
    @md5_queue    = nil
    @sha512_queue = nil
  end

  ##
  # Connects to the md5 and sha512 queues used by GemChecksummer

  def get_resources
    @md5_queue    = get_queue 'md5'
    @sha512_queue = get_queue 'sha512'
  end

  ##
  # Dequeues all items in the md5 and sha512 queues and writes them to
  # rubygems-<checksum>.swift.txt

  def run
    super do
      get_resources

      open 'rubygems-sha512.swift.txt', 'a' do |io|
        while item = @sha512_queue.deq(true) do
          name, checksum = item

          io.puts "#{checksum}  ./#{name}"
        end
      end

      open 'rubygems-md5.swift.txt', 'a' do |io|
        while item = @md5_queue.deq(true) do
          name, checksum = item

          io.puts "#{checksum}  ./#{name}"
        end
      end
    end
  end

end

