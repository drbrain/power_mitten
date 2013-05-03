require 'digest/md5'
require 'rbconfig'
require 'rubygems/installer'
require 'timeout'
require 'tmpdir'
require 'uri'

gem 'rdoc'
require 'rdoc'

##
# Runs rdoc on gems in a swift container

class PowerMitten::RDocer < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.cpu_multiplier = 1.5

  def initialize options # :nodoc:
    super options

    @gem_queue         = nil
    @rdoc_result_queue = nil

    @gems_container   = 'gems'
    @result_container = "rdoc-#{RDoc::VERSION}"
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
        @gem_queue.enq File.basename(object_info['name'], '.gem')
      end
    end
  end

  ##
  # Downloads +gem_file+ into +dest_dir+

  def download gem_file, dest_dir
    digest = Digest::MD5.new
    destination = File.join dest_dir, gem_file

    info "downloading #{gem_file} from #{@gems_container} to #{destination}"

    open destination, 'wb' do |io|
      @swift.read_object @gems_container, gem_file do |res|
        res.read_body do |chunk|
          digest << chunk

          io.write chunk
        end

        raise "checksum mismatch for #{@gems_container}/#{gem_file}" unless
          res['ETag'] == digest.hexdigest
      end
    end

    return destination
  end

  ##
  # Attaches to the +gem+ and +rdoc_result+ queues
  def get_queues
    @gem_queue         = get_queue 'gem'
    @rdoc_result_queue = get_queue 'rdoc_result'
  end

  ##
  # Retrieves the gemspec from +gem_file+

  def get_gemspec gem_file
    format = Gem::Format.from_file_by_path gem_file

    format.spec
  end

  ##
  # Runs rdoc on +gem_name+

  def rdoc gem_name
    status = 'unknown'
    gem_file = "#{gem_name}.gem"

    if @swift.object_info @result_container, gem_name then
      info "exists: #{gem_name}"
      @rdoc_result_queue.enq gem_name
      return
    end

    Dir.mktmpdir "rdoc-#{gem_name}" do |dir|
      gem = download gem_file, dir

      unpack gem, File.join(dir, 'gem')

      gem_spec = get_gemspec gem

      command = rdoc_command gem_spec, dir

      status = run_rdoc dir, command do |result_io|
        @swift.write_object @result_container, gem_name do |io|
          while chunk = result_io.gets do
            io.write chunk
          end
        end
      end
    end

    @swift.set_object_metadata(@result_container, gem_name,
                               'rdoc-result' => status)

    @rdoc_result_queue.enq gem_name

    info "finished: #{gem_name} #{status}"

    true
  rescue StandardError, Psych::SyntaxError => e
    @rdoc_result_queue.enq gem_name

    info "fail: #{gem_name} - #{e.message} (#{e.class}): #{e.backtrace.first}"

    false
  end

  ##
  # Generates an rdoc command for +gemspec+ that will generate RDoc from the
  # content in +dir+

  def rdoc_command gemspec, dir
    output_dir = File.join dir, 'output'
    rdoc = File.join(RbConfig::CONFIG["bindir"],
                     Gem.default_exec_format % 'rdoc')

    require_paths = gemspec.require_paths.map do |path|
      File.join dir, 'gem', path
    end

    extra_rdoc_files = gemspec.extra_rdoc_files.map do |path|
      File.join dir, 'gem', path
    end

    rdoc_options = [
      gemspec.rdoc_options,
      require_paths,
      extra_rdoc_files,
      '--verbose',
      '--debug',
      '--output', output_dir
    ].flatten.map do |arg| arg.to_s end

    rdoc_options.delete '--inline-source'
    rdoc_options.delete '--promiscuous'
    rdoc_options.delete '--one-file'
    rdoc_options.delete '-p'

    return rdoc, *rdoc_options
  end

  def run # :nodoc:
    super do
      swift = connect_swift

      swift.create_container @gems_container
      swift.create_container @result_container

      get_queues

      add_gems

      while gem = @gem_queue.deq(true) do
        rdoc gem
      end
    end
  end

  ##
  # Runs the rdoc +command+ in +dir+.  Yields the results of the command as an
  # IO.

  def run_rdoc dir, command
    results_r, results_w = IO.pipe
    results_w.sync = true

    notice "command: #{command}"
    pid = Process.spawn(*command,
                        cd: dir,
                        in: IO::NULL, out: results_w, err: results_w,
                        rlimit_rss: 1_000_000_000, rlimit_cpu: 600)

    result_thread = Thread.new do
      yield results_r
    end

  ensure
    Process.wait pid

    status = if $?.success? then
               'success'
             elsif $?.signaled? then
               'timeout'
             else
               'failure'
             end

    results_w.close
    result_thread.join

    return status
  end

  ##
  # Unpacks +gem+ into +dir+

  def unpack gem, dir
    Gem::Installer.new(gem, unpack: true).unpack dir
  end

end

