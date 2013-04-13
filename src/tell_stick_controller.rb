require 'chronic'
require 'securerandom'
require 'yaml'

require 'util/logging'
require 'util/persistence'
require 'util/scheduling'
require 'util/proc'
require 'util/hash'

require 'errormessage'
require 'device'
require 'schedule'
require 'temperature'

class TellStickController
  include Scheduling
  include Logging

  attr_accessor :schedules
  def initialize
    logger.info 'Starting up'
    config = YAML.load_file('config.yml')
    device_cache_refresh = config['device_cache_refresh'] ||= '5m'
    logger.debug 'Refreshing device cache every ' + device_cache_refresh
    @schedules = Hash.new # holds scheduled tasks
    @schedules_uuid = Hash.new
    scheduler.every device_cache_refresh do
      @devices = Device.find_all_devices
      logger.debug 'Refreshing device cache'
    end

    # Read temperature from Yr every hour
    yr_refresh = config['yr_refresh'] ||= '1h'
    scheduler.every yr_refresh do
      temperature = YrTemperature.get_reading
      temperature.save
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
    if !device.instance_of?(Device)
      return device
    end
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