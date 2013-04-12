require 'logger'
require 'rufus/scheduler'
require 'chronic'
require 'securerandom'
require 'sqlite3'

module Logging
  def logger
    Logging.logger
  end

  def self.logger
    @logger ||= Logger.new('housekeeper.log')
  end
end

module Persistence
  include Logging
  def db
    Persistence.db
  end

  def self.db
    @db ||= SQLite3::Database.open 'housekeeper.db'
  end

  def create_table(table, col_names)
    columns = []
    col_names.each do |name|
      columns << name + ' TEXT'
    end
    sql = "CREATE TABLE IF NOT EXISTS #{table} (#{columns.join(',')})"
    db.execute sql
  end

  def persist(*a)
    table = self.class.name
    col_names = []
    col_values = []
    a.each do |k|
      k.each do |key, value|
        col_names << key.to_s
        col_values << "'" + value + "'"
      end
    end

    create_table(table, col_names)
    sql = "INSERT INTO #{table}(#{col_names.join(',')}) VALUES(#{col_values.join(',')})"
    db.execute sql
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
  include Persistence
  attr_accessor :device, :timestamp, :action, :job, :uuid

  def initialize(device, timestamp, action, job, uuid)
    @device = device
    @timestamp = timestamp
    @action = action
    @job = job
    @uuid = uuid
  end


  def to_json(*a)
    {
        :device => device,
        :timestamp => timestamp,
        :action => action,
        :uuid => uuid,
    }.to_json(*a)
  end

  def save
    persist(
        {
            :uuid => uuid,
            :device_id => device.id,
            :timestamp => timestamp,
            :action => action,
        }
    )
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

class Hash
  #pass single or array of keys, which will be removed, returning the remaining hash
  def remove!(*keys)
    keys.each{|key| self.delete(key) }
    self
  end

  #non-destructive version
  def remove(*keys)
    self.dup.remove!(*keys)
  end
end

class TellStickController
  include Scheduling
  include Logging

  attr_accessor :schedules
  def initialize
    @schedules = Hash.new # holds scheduled tasks
    @schedules_uuid = Hash.new
    #TODO: persist in SQLite database
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
    device != nil ? device : ErrorMessage.new(401, 'No such device: ' + id)
  end

  def online_device(id)
    device = list_devices[id]
    device != nil ? device.online : ErrorMessage.new(401, 'No such device: ' + id)
  end

  def offline_device(id)
    device = list_devices[id]
    device != nil ? device.offline : ErrorMessage.new(401, 'No such device: ' + id)
  end

  def toggle_device(id)
    device = list_devices[id]
    device != nil ? device.toggle : ErrorMessage.new(401, 'No such device: ' + id)
  end

  def schedule(device, action, timestamp)
    parsed_timestamp = Chronic.parse(timestamp)
    logger.info('Scheduling device ' + device.id + ' (' + device.name + ') for ' + action.name + ' at ' + parsed_timestamp.to_s)
    uuid = SecureRandom.uuid
    schedule = Schedule.new(device, parsed_timestamp.to_s, action.name, nil, uuid)
    #@schedules << schedule
    job = scheduler.at parsed_timestamp do
      logger.info('Running scheduled action...')
      action.call
      @schedules.remove!(schedule.job.job_id)
      @schedules_uuid.remove!(schedule.uuid)
    end
    schedule.job = job
    @schedules[job.job_id] = schedule
    @schedules_uuid[schedule.uuid] = job.job_id
    schedule.save
    schedule
  end

  def unschedule(job_id)
    schedule = @schedules[job_id]
    if schedule != nil
      logger.info('Removing scheduled task ' + schedule.uuid + ' (' + schedule.action + ' device ' + schedule.device.name + ')')
      scheduler.unschedule(job_id)
      @schedules.remove!(job_id)
      @schedules_uuid.remove!(schedule.uuid)
      'Schedule ' + schedule.uuid + ' removed.'
    else
      ErrorMessage.new(401, 'No such schedule')
    end
  end

  def unschedule_by_uuid(uuid)
    job_id = @schedules_uuid[uuid]
    unschedule(job_id)
  end

  def list_scheduled_tasks
    sched_list = []
    @schedules.each do |k, v|
      sched_list << v
    end
    sched_list
  end
end