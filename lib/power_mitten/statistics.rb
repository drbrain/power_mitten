##
# Computes statistics for a data set but does not store the data set.
#
# Provides a count of items added to the set along with the mean and standard
# deviation.

class PowerMitten::Statistics < PowerMitten::Task

  config = PowerMitten::Configuration.new self
  config.maximum_workers = 1

  describe_label :name,               '%-s',   ['Name',   '%-s']
  describe_label :items,              '%6d',   ['Items',  '%6d', 6]
  describe_label :mean,               '%6g',   ['Mean',   '%6g', 6]
  describe_label :standard_deviation, 'σ %6g', ['StdDev', '%6g', 6]

  ##
  # The mean (average) of the added values

  attr_reader :mean

  ##
  # The number of values added

  attr_reader :items

  ##
  # The name of this instance

  attr_reader :name

  ##
  # Creates a new statistics recorder.  +options+ must include a +:name+
  # parameter.

  def initialize options
    super

    @name  = options[:name]

    @items           = 0
    @mean            = 0.0
    @mutex           = Mutex.new
    @M_2             = 0.0
  end

  ##
  # Adds +value+ to the statistics data set, returns the index of the added
  # item
  #--
  # This implementation is numerically stable.  See:
  # http://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Online_algorithm

  def add_value value
    @mutex.synchronize do
      index = @items += 1

      delta = value - @mean
      @mean += delta / index
      @M_2 += delta * (value - @mean)

      index
    end
  end

  def description # :nodoc:
    super do |description|
      description[:name]               = @name.sub 'Statistic-', ''
      description[:items]              = @items
      description[:mean]               = @mean
      description[:standard_deviation] = standard_deviation
    end
  end

  def run # :nodoc:
    service = nil

    super do
      service ||= register self, @name

      service.thread.join
    end
  end

  ##
  # The sample variance of the data

  def sample_variance
    @mutex.synchronize do
      @M_2 / (@items - 1)
    end
  end

  ##
  # The standard deviation of the data

  def standard_deviation
    Math.sqrt sample_variance
  end

end

