require 'nokogiri'
require 'open-uri'
require 'chronic'
require 'yaml'
require 'temper2-ruby/temper2'

$LOAD_PATH.unshift File.dirname(__FILE__)
require 'util/logging'
require 'util/persistence'
require 'util/scheduling'

require 'errormessage'

class Temperature
  include Logging
  include Persistence
  attr_accessor :temperature_reading, :source, :timestamp

  def to_json(*a)
    {
        :temperature_reading => temperature_reading,
        :source => source,
        :timestamp => timestamp,
    }.to_json(*a)
  end

  def initialize(temperature_reading, source, timestamp)
    @temperature_reading = temperature_reading
    @source = source
    @timestamp = timestamp
  end

  def save
    persist({
        :temperature_reading => temperature_reading,
        :source => source,
        :timestamp => timestamp,
    })
  end

  def self.find_all
    temperature_rows = self.find_all
    if nil == temperature_rows
      return []
    end
    temperatures = []
    temperature_rows.each do |temperature_reading, source, timestamp|
      temperatures << Temperature.new(temperature_reading, source, timestamp)
    end
    temperatures
  end

  def self.find_by_source(source)
    temperature_rows = self.find_by_column(:source, source)
    if nil == temperature_rows
      return []
    end
    temperatures = []
    temperature_rows.each do |temperature_reading, source, timestamp|
      temperatures << Temperature.new(temperature_reading, source, timestamp)
    end
    temperatures
  end

  def self.find_highest(limit)
    sql = "SELECT * from #{self.inspect} ORDER BY temperature_reading DESC LIMIT #{limit}"
    logger.debug sql
    self.select sql
  end

  def self.find_lowest(limit)
    sql = "SELECT * from #{self.inspect} ORDER BY temperature_reading ASC LIMIT #{limit}"
    logger.debug sql
    self.select sql
  end

  def self.find_latest_by_source(source, limit)
    sql = "SELECT * from #{self.inspect} WHERE source = '#{source}' ORDER BY timestamp DESC LIMIT #{limit}"
    logger.debug sql
    self.select sql
  end

  def self.select(sql)
    begin
      stm = db.prepare sql
      rs = stm.execute
    rescue SQLite3::SQLException => e
      puts e.backtrace
      rs = nil
    end
    if rs != nil
      temperatures = []
      rs.each do |temperature_reading, source, timestamp|
        temperatures << Temperature.new(temperature_reading, source, timestamp)
      end
      temperatures
    end
  end
end

class YrTemperature < Temperature
  @source = 'yr'

  def self.get_reading
    logger.debug 'Fetching temperature reading from Yr'
    config = YAML.load_file('config.yml')
    url = config['yr_url']
    weatherstation = config['yr_weatherstation']
    document = Nokogiri::XML(open(url))
    temperature_reading = document.xpath("//weatherdata/observations/weatherstation[@name='#{weatherstation}']/temperature/@value")
    timestamp = document.xpath("//weatherdata/observations/weatherstation[@name='#{weatherstation}']/temperature/@time")
    Temperature.new(temperature_reading.to_s.to_f, @source, Chronic.parse(timestamp.to_s).localtime.to_s)
  end

  def self.find_all
    find_by_source(@source)
  end
end

class CachedYrTemperature < YrTemperature
  include Scheduling
  def self.get_reading
    @yrtemperature ||= YrTemperature.get_reading
  end

  def self.set_temperature(temperature)
    @yrtemperature = temperature
  end
end

class InsideTemperature < Temperature
  @source = 'inside'

  def self.get_reading
    begin
      temperature_reading = Temper2::read_inner_sensor
      Temperature.new(temperature_reading, @source, Chronic.parse(Time.now.to_s).localtime.to_s)
    rescue Exception => e
      ErrorMessage.new(400, "Can't get temperature reading")
    end
  end

  def self.find_all
    find_by_source(@source)
  end
end

class OutsideTemperature < Temperature
  @source = 'outside'

  def self.get_reading
    begin
      temperature_reading = Temper2::read_outer_sensor
      Temperature.new(temperature_reading, @source, Chronic.parse(Time.now.to_s).localtime.to_s)
    rescue Exception => e
      ErrorMessage.new(400, "Can't get temperature reading")
    end
  end

  def self.find_all
    find_by_source(@source)
  end
end

class TemperatureSensors
  attr_accessor :sensors

  def initialize
    @sensors = []
    @sensors << CachedYrTemperature
    @sensors << OutsideTemperature
    @sensors << InsideTemperature
  end

  def get_sensors
    @sensors
  end
end