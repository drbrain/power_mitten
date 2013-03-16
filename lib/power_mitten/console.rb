require 'curses'

class PowerMitten::Console < PowerMitten::Node

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  def initialize options
    super options

    @queue_stats = Hash.new 0

    @wait = 2.0
    @type = 'Irb' if @localhost
  end

  ##
  # Displays a view of the active services on the control node

  def console
    Curses.init_screen
    @window = Curses::Window.new 0, 0, 0, 0

    loop do
      @window.clear
      @window.setpos 0, 0

      @control.services.sort_by do |class_name, _|
        class_name
      end.each do |class_name, names|
        next if names.empty?
        @window.setpos @window.cury, 0

        @window.addstr "#{class_name}:"
        @window.setpos @window.cury + 1, 2

        names.sort_by do |name, _|
          name
        end.each do |name, service|
          show class_name, name, service
        end
      end

      @window.refresh

      sleep @wait
    end

  ensure
    Curses.close_screen
  end

  def run
    super do
      console
    end
  end

  def show class_name, name, service
    begin
      object = service.object
    rescue DRb::DRbConnError
      return
    end

    case class_name
    when 'Queue' then
      last_size = @queue_stats[name]

      size = object.size
      delta = size - last_size
      items_per_second = delta / @wait

      str = "%s %d items %d waiting %+d (%0.1f/s)" % [
        name, size, object.num_waiting, delta, items_per_second
      ]

      @window.addstr str

      @queue_stats[name] = size
    when 'Mutex' then
      locked = object.locked? ? 'locked' : 'unlocked'

      @window.addstr "#{name} #{locked}"
    else
      @window.addstr name
    end

    @window.setpos @window.cury + 1, 2
  end

end

