##
# Monitors the active tasks and services and displays their statistics

class PowerMitten::Console < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  def initialize options # :nodoc:
    require 'curses'
    require 'io/console'
    require 'power_mitten/console/row_formatter'

    super options

    @row_formatters = nil
    @queue_stats    = nil
    @wait           = 2.0
  end

  ##
  # Collates +services+ by group.  If the group is "Mitten" (the default
  # group) those services are grouped by name.  Services within the "Mitten"
  # group do not have homogeneous descriptions.

  def collate_descriptions services
    services.group_by do |name, group,|
      group == 'Mitten' ? name : group
    end
  end

  ##
  # Displays a view of the active services on the control task

  def console
    reinitialize

    Curses.init_screen
    @window         = Curses::Window.new 0, 0, 0, 0

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

  ##
  # Called this when the console reconnects to control to reset statistics and
  # formatters.

  def reinitialize
    @queue_stats    = Hash.new 0
    @row_formatters = {}
  end

  ##
  # Retrieves a row formatter for the Task +description+ belongs to

  def row_formatter_for description
    klass = description[:klass]

    @row_formatters[klass] ||= PowerMitten::Console::RowFormatter.new klass
  end

  def run # :nodoc:
    super do
      console
    end
  end

  ##
  # Returns a name, group and description for each item in +services+ that is
  # alive.

  def service_descriptions services
    services.map do |_, name, service,|
      begin
        description = service.description
        [name, description[:group], description]
      rescue DRb::DRbConnError
      end
    end.compact
  end

  ##
  # Displays +line+ with an optional +indent+

  def show_line line, indent = nil
    @window.setpos @window.cury, indent if indent
    @window.addstr line
    @window.setpos @window.cury + 1, 0
  end

  ##
  # Shows the task +services+ in +group_name+

  def show_tasks group_name, services
    /^Mitten-(?<short_name>.*)/ =~ group_name

    descriptions = services.map { |_, _, description| description }

    row_formatter = row_formatter_for descriptions.first

    lines = row_formatter.format descriptions

    lines.each_with_index do |line, index|
      line << " - #{short_name}" if short_name and index.zero?
      show_line line
    end
  end

  def show_tasks_aggregate group_name, tasks
  end

  ##
  # Shows +services+ in +group_name+

  def show_services group_name, services
    @window.setpos @window.cury, 0

    show_line "#{group_name}:"

    services.each do |name, group, description|
      case group
      when 'Queue' then
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
      when 'Mutex' then
        name = $'
        locked = service.locked? ? 'locked' : 'unlocked'

        show_line "#{name} #{locked}", 2
      else
        show_line "#{name} [unknown]", 2
      end
    end
  end

  ##
  # Sorts services by name.  The control service is always at the top

  def sort_descriptions services
    services.sort_by do |name,|
      case name
      when 'Mitten-control' then
        ''
      else
        name
      end
    end
  end

  ##
  # Discovers and updates service descriptions

  def update
    descriptions = service_descriptions services

    sorted = sort_descriptions descriptions

    collated = collate_descriptions sorted

    collated.each do |group_name, services|
      update_service group_name, services
    end
  end

  ##
  # Updates the consoles for +services+ in +group_name+

  def update_service group_name, services
    case group_name
    when /^Mitten/,
         'Statistics'  then
      show_tasks group_name, services
    when 'Mutex',
         'Queue' then
      show_services group_name, services
    end
  end


end

