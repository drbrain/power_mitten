require 'curses'
require 'io/console'

class PowerMitten::Console < PowerMitten::Node

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  def initialize options
    super options

    @queue_stats = Hash.new 0

    @wait = 2.0
    @type = 'Console' if @localhost
  end

  def collate_services services
    collated = Hash.new { |h, k| h[k] = [] }

    services.each do |_, name, service, _|
      case name
      when /(Mutex|Queue)-/ then
        collated[$1] << [name, service]
      else
        collated[name] << [name, service]
      end
    end

    collated
  end

  ##
  # Displays a view of the active services on the control node

  def console
    Curses.init_screen
    @window = Curses::Window.new 0, 0, 0, 0

    trap 'WINCH' do
      rows, cols = IO.console.winsize
      Curses.resizeterm rows, cols
      @window.resize    rows, cols
    end

    loop do
      @window.clear
      @window.setpos 0, 0

      update

      @window.refresh

      sleep @wait
    end

  ensure
    Curses.close_screen
  end

  def live_services services
    alive = services.select do |_, _, service,|
      begin
        if DRb::DRbObject === service then
          service.send :method_missing, :object_id
        else
          true
        end
      rescue DRb::DRbConnError
      end
    end
  end

  def run
    super do
      console
    end
  end

  def show_line line, indent = nil
    @window.setpos @window.cury, indent if indent
    @window.addstr line
    @window.setpos @window.cury + 1, 0
  end

  def show_nodes group_name, nodes
    nodes.each do |name, node|
      begin
        here = nil

        case name
        when 'Mitten-control' then
          show_line "control #{node.description}"
        when /^Mitten-/ then
          name = $'

          here = ' (me)' if self == node

          show_line "#{name} #{node.description}#{here}"
        else
          show_line group_name
        end
      rescue DRb::DRbConnError
      end
    end
  end

  def show_services group_name, services
    @window.setpos @window.cury, 0

    show_line "#{group_name}:"

    services.each do |name, service|
      case name
      when /^Queue-/ then
        name = $'
        last_size = @queue_stats[name]

        queue = service

        size = queue.size
        delta = size - last_size
        items_per_second = delta / @wait

        str = "%s %d items %d waiting %+d (%0.1f/s)" % [
          name, size, queue.num_waiting, delta, items_per_second
        ]

        show_line str, 2

        @queue_stats[name] = size
      when /Mutex-/ then
        name = $'
        locked = service.locked? ? 'locked' : 'unlocked'

        show_line "#{name} #{locked}", 2
      else
        show_line "#{name} [unknown]", 2
      end
    end
  end

  def sort_services services
    services.sort_by do |_, name,|
      case name
      when 'Mitten-control' then
        ''
      else
        name
      end
    end
  end

  def update
    alive = live_services services

    sorted = sort_services alive

    collated = collate_services sorted

    collated.each do |group_name, services|
      update_service group_name, services
    end
  end

  def update_service group_name, services
    case group_name
    when /^Mitten-/ then
      show_nodes group_name, services
    when 'Mutex', 'Queue' then
      show_services group_name, services
    end
  end

end

