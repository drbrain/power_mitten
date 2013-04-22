class PowerMitten::Console < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  def initialize options
    require 'curses'
    require 'io/console'
    require 'power_mitten/console/row_formatter'

    super options

    @row_formatters = nil
    @queue_stats    = nil
    @wait           = 2.0
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

  def get_descriptions items
    items.map do |_, task|
      begin
        task.description
      rescue DRb::DRbConnError
      end
    end.compact
  end

  def live_services services
    services.select do |_, _, service,|
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

  def show_tasks group_name, tasks
    /^Mitten-(?<short_name>.*)/ =~ group_name

    groups = tasks.group_by { |name,| name }

    groups.each_value do |items|
      descriptions = get_descriptions items

      next if descriptions.empty?

      row_formatter = row_formatter_for descriptions.first

      lines = row_formatter.format descriptions

      lines.each_with_index do |line, index|
        line << " - #{short_name}" if index.zero?
        show_line line
      end
    end
  end

  def show_tasks_aggregate group_name, tasks
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
      if services.size > 2 then
        show_tasks_aggregate group_name, services
      else
        show_tasks group_name, services
      end
    when 'Mutex', 'Queue' then
      show_services group_name, services
    end
  end

end

