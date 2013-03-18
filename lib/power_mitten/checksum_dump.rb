class PowerMitten::ChecksumDump < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  attr_reader :md5_queue
  attr_reader :sha512_queue

  def initialize options
    super options

    @gem_queue    = nil
    @md5_queue    = nil
    @sha512_queue = nil
  end

  def get_queues
    @md5_queue    = get_queue 'md5'
    @sha512_queue = get_queue 'sha512'
  end

  def run
    super do
      get_queues

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

