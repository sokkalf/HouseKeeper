require 'nokogiri'
require 'open-uri'
require 'chronic'
require 'yaml'

$LOAD_PATH.unshift File.dirname(__FILE__)
require 'util/logging'
require 'util/persistence'

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

  def self.find_lowest(limit)
    sql = "SELECT * from #{self.inspect} ORDER BY temperature_reading ASC LIMIT #{limit}"
    logger.debug sql
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
