require 'rest_client'
require 'json'

class DataShipper
  def self.ship_data(url, temperatures)
    response = RestClient.put(url, temperatures.to_json, :content_type => :json)
    if response.code == 200
      temperatures.uniq.each do |temperature|
        Temperature.delete_by_columns(:temperature_reading => temperature.temperature_reading,
                                      :source => temperature.source, :timestamp => temperature.timestamp)
      end
    else
    end
  end
end