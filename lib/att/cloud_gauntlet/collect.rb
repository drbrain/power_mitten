require 'thread'

class ATT::CloudGauntlet::Collect < ATT::CloudGauntlet::Node

  def initialize options = {}
    super

    @result_container    = 'rdoc-4.0'
    @status_thread_count = 32
    @chunk_thread_count  = @status_thread_count / 8

    @failed        = []
    @success_count = 0
    @timeout       = []
    @total         = 0

    @failed_mutex  = Mutex.new
    @success_mutex = Mutex.new
    @timeout_mutex = Mutex.new
    @total_mutex   = Mutex.new
    @status_queue  = Queue.new
    @chunk_queue   = Queue.new
  end

  def percent count
    (count.to_f / @total) * 100
  end

  def read_object_chunk chunk
    chunk.each do |object_info|
      name = object_info['name']

      @status_queue.enq name
    end
  end

  def read_objects
    Thread.new do
      chunk_threads = (0...@chunk_thread_count).map do
        Thread.new do
          while chunk = @chunk_queue.deq do
            read_object_chunk chunk
          end
        end
      end

      @swift.chunk_objects @result_container, nil, 1000 do |chunk|
        @chunk_queue.enq chunk

        @total += chunk.size
      end

      @chunk_thread_count.times do
        @chunk_queue.enq nil
      end

      @status_thread_count.times do
        @status_queue.enq nil
      end

      chunk_threads.each do |thread|
        thread.join
      end
    end
  end

  def read_status name
    metadata = @swift.object_metadata @result_container, name

    case status = metadata['rdoc-result']
    when 'success' then
      @success_mutex.synchronize do
        @success_count += 1
      end
    when 'timeout' then
      @timeout_mutex.synchronize do
        @timeout << name
      end
    when 'failure' then
      @failed_mutex.synchronize do
        @failed << name
      end
    when nil then
      @swift.delete_object @result_container, name
      @failed_mutex.synchronize do
        @failed << name
      end
    else
      puts "unknown status #{status.inspect} for #{name}"
      @failed_mutex.synchronize do
        @failed << name
      end
    end
  rescue NoMethodError => e
    puts "unknown status #{e.message} for #{name}"
    @failed_mutex.synchronize do
      @failed << name
    end
  end

  def read_statuses
    threads = (0...@status_thread_count).map do
      Thread.new do
        while name = @status_queue.deq do
          read_status name
        end
      end
    end

    threads.each do |thread|
      thread.join
    end
  end

  def report
    puts "total: #{@total}"
    puts

    puts "successful: %d %0.1f%%" % [@success_count, percent(@success_count)]
    puts

    puts "failed: %d %0.1f%%" % [@failed.length, percent(@failed.length)]
    report_collection @failed

    puts "timeout: %d %0.1f%%" [@timeout.length, percent(@timeout.length)]
    report_collection @timeout
  end

  def report_collection collection
    return if collection.empty?

    collection.sort.each do |name|
      puts "\t#{name}"
    end

    puts
  end

  def run
    super do
      connect_swift

      @swift.create_container @result_container

      container = @swift.containers.find do |container|
        container['name'] == @result_container
      end

      puts "#{container['name']} has #{container['count']} items"

      status_thread = Thread.new do
        loop do
          sleep 5
          puts "chunk_queue: #{@chunk_queue.length} " \
               "status_queue: #{@status_queue.length}"
        end
      end

      thread = read_objects

      read_statuses

      thread.join

      status_thread.kill

      report
    end
  end

end
