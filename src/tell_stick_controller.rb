require 'logger'
require 'rufus/scheduler'
require 'chronic'

module Logging
  def logger
    Logging.logger
  end

  def self.logger
    @logger ||= Logger.new('housekeeper.log')
  end
end

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
end

class Schedule
  attr_accessor :device, :timestamp, :action

  def initialize(device, timestamp, action)
    @device = device
    @timestamp = timestamp
    @action = action
  end

  def to_json(*a)
    {
        :device => device,
        :timestamp => timestamp,
        :action => action,
    }.to_json(*a)
  end
end

module Scheduling
  def scheduler
    Scheduling.scheduler
  end

  def self.scheduler
    @scheduler ||= Rufus::Scheduler.start_new
  end
end

class TellStickController
  include Scheduling
  include Logging

  attr_accessor :schedules
  def initialize
    @schedules = [] # holds scheduled tasks
  end

  def list_devices
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

  def show_device(id)
    device = list_devices[id]
    device != nil ? device : ErrorMessage.new(501, 'No such device: ' + id)
  end

  def online_device(id)
    device = list_devices[id]
    device != nil ? device.online : ErrorMessage.new(501, 'No such device: ' + id)
  end

  def offline_device(id)
    device = list_devices[id]
    device != nil ? device.offline : ErrorMessage.new(501, 'No such device: ' + id)
  end

  def toggle_device(id)
    device = list_devices[id]
    device != nil ? device.toggle : ErrorMessage.new(501, 'No such device: ' + id)
  end

  def schedule(device, action, timestamp)
    parsed_timestamp = Chronic.parse(timestamp)
    logger.info('Scheduling device ' + device.id + ' (' + device.name + ') for ' + action.name + ' at ' + parsed_timestamp.to_s)
    schedule = Schedule.new(device, parsed_timestamp.to_s, action.name)
    @schedules << schedule
    scheduler.at parsed_timestamp do
      logger.info('Running scheduled action...')
      action.call
      @schedules.delete(schedule)
    end
    schedule
  end

  def list_scheduled_tasks
    @schedules
  end
end