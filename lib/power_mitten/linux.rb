##
# Retrieves RSS bytes on linux

module PowerMitten::Linux

  PAGESIZE = `getconf PAGESIZE`.to_i

  ##
  # Returns the Resident Set Size in kilobytes for the current process

  def self.resident_set_size
    _, rss_pages, = File.read('/proc/self/statm').split ' ', 3

    rss_pages * PAGESIZE
  end

end

