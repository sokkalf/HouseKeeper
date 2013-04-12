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

  def self.included(o)
    o.extend(FindMethods)
  end

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
    logger.debug sql
    begin
      db.execute sql
    rescue SQLite3::SQLException => e
      logger.error 'Error inserting row in database'
    end
  end

  module FindMethods
    include Persistence

    def find_all
      table = self.inspect
      sql = "SELECT * FROM #{table}"
      begin
        stm = db.prepare sql
        stm.execute
      rescue SQLite3::SQLException => e
        nil
      end
    end

    def find_by_column(col, value)
      table = self.inspect
      sql = "SELECT * FROM #{table} WHERE #{col} = '#{value}'"
      logger.debug sql
      begin
        stm = db.prepare sql
        stm.execute
      rescue SQLite3::SQLException => e
        nil
      end
    end

    def delete_by_column(col, value)
      table = self.inspect
      sql = "DELETE FROM #{table} WHERE #{col} = '#{value}'"
      logger.debug sql
      begin
        db.execute sql
      rescue SQLite3::SQLException => e
        nil
      end
    end
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

  def self.find_all_schedules
    schedule_rows = self.find_all
    if nil == schedule_rows
      return []
    end
    schedules = []
    schedule_rows.each do |uuid, device_id, timestamp, action|
      device = Device.find_by_id(device_id)
      schedules << Schedule.new(device, timestamp, action, nil, uuid)
    end
    schedules
  end

  def self.find_by_uuid(uuid)
    schedule_rows = self.find_by_column(:uuid, uuid)
    if nil == schedule_rows
      return nil
    end
    schedules = []
    schedule_rows.each do |uuid, device_id, timestamp, action|
      device = Device.find_by_id(device_id)
      schedules << Schedule.new(device, timestamp, action, nil, uuid)
    end
    schedules[0]
  end

  def self.delete_by_uuid(uuid)
    delete_by_column(:uuid, uuid)
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

class Proc
  attr_accessor :name
end

class TellStickController
  include Scheduling
  include Logging

  attr_accessor :schedules
  def initialize
    @schedules = Hash.new # holds scheduled tasks
    @schedules_uuid = Hash.new
    scheduler.every '5m' do
      @devices = Device.find_all_devices
      logger.debug 'Refreshing device cache'
    end

    Schedule.find_all_schedules.each do |sched|
      if Chronic.parse(sched.timestamp) > Time.now
        case sched.action
          when 'online'
            action = Proc.new{online_device(sched.device.id)}
          when 'offline'
            action = Proc.new{offline_device(sched.device.id)}
          when 'toggle'
            action = Proc.new{toggle_device(sched.device.id)}
          else
            action = nil
        end
        if action != nil
          action.name = sched.action
          schedule(sched.device, action, sched.timestamp, sched.uuid)
        end
      else
        Schedule.delete_by_uuid(sched.uuid)
      end
    end

  end

  def list_devices
    @devices != nil ? @devices : @devices = Device.find_all_devices
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

  def schedule(device, action, timestamp, uuid)
    parsed_timestamp = Chronic.parse(timestamp)
    logger.info('Scheduling device ' + device.id + ' (' + device.name + ') for ' + action.name + ' at ' + parsed_timestamp.to_s)
    uuid = uuid != nil ? uuid : SecureRandom.uuid
    schedule = Schedule.new(device, parsed_timestamp.to_s, action.name, nil, uuid)
    job = scheduler.at parsed_timestamp do
      logger.info('Running scheduled action...')
      action.call
      @schedules.remove!(schedule.job.job_id)
      @schedules_uuid.remove!(schedule.uuid)
      Schedule.delete_by_uuid(schedule.uuid)
    end
    schedule.job = job
    @schedules[job.job_id] = schedule
    @schedules_uuid[schedule.uuid] = job.job_id
    if Schedule.find_by_uuid(schedule.uuid) == nil
      schedule.save
    end
    schedule
  end

  def unschedule(job_id)
    schedule = @schedules[job_id]
    if schedule != nil
      logger.info('Removing scheduled task ' + schedule.uuid + ' (' + schedule.action + ' device ' + schedule.device.name + ')')
      scheduler.unschedule(job_id)
      @schedules.remove!(job_id)
      @schedules_uuid.remove!(schedule.uuid)
      Schedule.delete_by_uuid(schedule.uuid)
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