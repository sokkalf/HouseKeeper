require 'util/logging'

class Device
  include Logging
  attr_accessor :id, :name, :status

  def initialize(id, name, status)
    @id = id
    @name = name
    @status = status
  end

  def to_json(*a)
    if @error == nil
      {
          :id => @id,
          :name => @name,
          :status => @status,
      }.to_json(*a)
    else
      {
          :id => @id,
          :name => @name,
          :status => @status,
          :error => @error,
      }.to_json(*a)
    end
  end

  def online
    logger.info('Onlining device ' + @id + ' (' + @name + ')')
    if @status == 'ON'
      logger.info('Device ' + @id + ' (' + @name + ') already online, doing nothing.')
      return self
    end
    output = %x{tdtool --on #{@id}}
    if (output =~ /Success$/) != nil
      logger.info('Onlining device ' + @id + ' (' + @name + ') was successful')
      @status = 'ON'
    else
      class << self
        attr_accessor :error
      end
      self.error = ErrorMessage.new(502, 'Device not onlined').message
      logger.info('Onlining device ' + @id + ' (' + @name + ') failed with error : ' + self.error)
    end
    self
  end

  def offline
    logger.info('Offlining device ' + @id + ' (' + @name + ')')
    if @status == 'OFF'
      logger.info('Device ' + @id + ' (' + @name + ') already offline, doing nothing.')
      return self
    end
    output = %x{tdtool --off #{@id}}
    if (output =~ /Success$/) != nil
      logger.info('Offlining device ' + @id + ' (' + @name + ') was successful')
      @status = 'OFF'
    else
      class << self
        attr_accessor :error
      end
      self.error = ErrorMessage.new(502, 'Device not offlined').message
      logger.info('Offlining device ' + @id + ' (' + @name + ') failed with error : ' + self.error)
    end
    self
  end

  def toggle
    if @status == 'OFF'
      online
    else
      offline
    end
  end

  def self.find_all_devices
    output = %x{tdtool --list}
    lines = output.split("\n")
    lines.shift # whack the first line
    devices = Hash.new
    lines.each do |line|
      #TODO: find a better way to do this..
      id=line.split[0] # first element
      name=line.split.slice(1..-2).join(' ') # middle elements
      status=line.split[-1] # last element
      device = Device.new(id, name, status)
      devices = {device.id => device}
    end
    devices
  end

  def self.find_by_id(id)
    find_all_devices[id]
  end
end
