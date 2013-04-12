require 'util/logging'

class ErrorMessage
  include Logging
  attr_accessor :error, :message

  def initialize(error, message)
    @error = error
    @message = message
    logger.error(message)
  end

  def to_json(*a)
    {
        :error => error,
        :message => message,
    }.to_json(*a)
  end
end