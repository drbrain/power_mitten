require 'net/http/persistent'

##
# Downloads gems from rubygems.org into a swift container

class PowerMitten::GemDownloader < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.cpu_multiplier = 8

  self.label_order = [
    :checked,
    :downloaded,
    :failed
  ] + PowerMitten::Task.label_order

  describe_label :checked,    "%d\u2713", ['Checked',    '%5d']
  describe_label :downloaded, "%d\u2913", ['Downloaded', '%5d']
  describe_label :failed,     "%d\u20E0", ['Failed',     '%5d']

  def initialize options # :nodoc:
    super options

    @swift          = nil
    @gem_name_queue = nil
    @gem_queue      = nil

    @base_uri = URI 'http://production.s3.rubygems.org/gems/'
    @http     = Net::HTTP::Persistent.new

    @first_downloader = false
    @gems_container   = 'gems'

    @checked    = 0
    @downloaded = 0
    @failed     = 0
  end

  ##
  # Retrieves gem names from rubygems.org and adds them to the gem_name queue.
  #--
  # TODO move this to a separate service, it is very expensive memory-wise

  def add_gem_names
    add_gem_names_mutex = get_mutex 'add_gem_names'

    add_gem_names_mutex.synchronize do
      break unless @gem_name_queue.empty?

      get_gem_names.each do |name|
        @gem_name_queue.enq name
      end
    end
  end

  def description # :nodoc:
    super do |description|
      description[:checked]    = @checked
      description[:downloaded] = @downloaded
      description[:failed]     = @failed
    end
  end

  ##
  # Downloads the gem with +name+ and stores it in swift, then adds the name
  # to gem_name queue

  def download name
    @checked += 1
    gem_name = "#{name}.gem"

    if gem_exists? gem_name then
      @gem_queue.push name

      info "#{gem_name} exists"

      return
    end

    uri = @base_uri + "#{name}.gem"

    source_etag = nil
    dest_etag   = nil

    @http.request uri do |source_res|
      break unless etag = source_res['ETag']
      source_etag = etag.delete '"'

      dest_etag = @swift.write_object @gems_container, gem_name do |io|
        source_res.read_body do |chunk|
          io.write chunk
        end
      end
    end

    if dest_etag == source_etag then
      @gem_queue.push name

      info "#{gem_name} downloaded"

      @downloaded += 1
    else
      @gem_name_queue.push name
      @swift.delete_object @gems_container, gem_name

      info "#{gem_name} download failed"
      @failed += 1
    end
  end

  ##
  # Returns true if +gem_name+ exists in the gems container

  def gem_exists? gem_name
    @swift.object_info @gems_container, gem_name
  end

  ##
  # Retrieves the gem names from rubygems.org

  def get_gem_names
    fetcher = Gem::SpecFetcher.fetcher

    list, = fetcher.available_specs(:complete)

    tuples = list.values.first

    tuples.map do |tuple,|
      tuple = tuple.to_a
      case tuple.last
      when Gem::Platform::RUBY then
        tuple[0, 2]
      else
        tuple
      end.join '-'
    end
  end

  ##
  # Attaches to the gem_name and gem queues

  def get_queues
    @gem_name_queue = get_queue 'gem_name'
    @gem_queue      = get_queue 'gem'
  end

  def run # :nodoc:
    super do
      @checked    = 0
      @downloaded = 0
      @failed     = 0

      swift = connect_swift

      swift.create_container @gems_container

      get_queues

      add_gem_names

      while name = @gem_name_queue.deq(true) do
        download name
      end
    end
  end

end

