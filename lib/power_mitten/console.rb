##
# Monitors the active tasks and services and displays their statistics

class PowerMitten::Console < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  attr_accessor :window # :nodoc:

  def initialize options # :nodoc:
    require 'curses'
    require 'io/console'
    require 'power_mitten/console/row_formatter'

    super options

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

  ##
  # Retrieves a row formatter for the Task +description+ belongs to

  def row_formatter_for description
    PowerMitten::Console::RowFormatter.new description[:klass]
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
  # Displays +line+

  def show_line line
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
    show_tasks group_name, services
  end


end

