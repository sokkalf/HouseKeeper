require 'logger'

module Logging
  def logger
    Logging.logger
  end

  def self.logger
    @logger ||= Logger.new('housekeeper.log')
  end
end