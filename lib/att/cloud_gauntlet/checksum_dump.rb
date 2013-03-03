require 'att/cloud_gauntlet/node'

require 'digest/md5'
require 'digest/sha2'

gem 'rdoc'
require 'rdoc'

class ATT::CloudGauntlet::ChecksumDump < ATT::CloudGauntlet::Node

  attr_reader :md5_queue
  attr_reader :sha512_queue

  def initialize options
    super options

    @gem_queue    = nil
    @md5_queue    = nil
    @sha512_queue = nil
  end

  def get_queues
    @md5_queue    = get_queue :md5_queue
    @sha512_queue = get_queue :sha512_queue
  end

  def run
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

