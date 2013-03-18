##
# Formats rows of information from a task including automatically sizing
# columns so everything aligns

class PowerMitten::Console::RowFormatter

  attr_reader :klass # :nodoc:

  ##
  # Creates a new RowFormatter using column information from Task +klass+

  def initialize klass
    @klass = klass

    @column_descriptions = klass.column_descriptions

    @headers = @column_descriptions.map do |_, header, format,|
      header
    end
  end

  def == other # :nodoc:
    self.class === other and @klass == other.klass
  end

  ##
  # Formats +descriptions+ and returns formatter rows

  def format descriptions
    formatted = format_rows descriptions

    aligned = formatted.transpose.map do |column|
      width = column.map { |entry| entry.length }.max

      column.map { |entry| entry.rjust width }
    end

    aligned.transpose.map do |row|
      row.join ' '
    end
  end

  ##
  # Adds headers and applies column formats to the rows in +descriptions+

  def format_rows descriptions
    formatted = descriptions.map do |description|
      @column_descriptions.map do |field, _, format,|
        format % description[field]
      end
    end

    [@headers].concat formatted
  end

end

