require 'nokogiri'
require 'open-uri'
require 'chronic'
require 'yaml'

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
    Temperature.new(temperature_reading.to_s, @source, Chronic.parse(timestamp.to_s).localtime.to_s)
  end
end
