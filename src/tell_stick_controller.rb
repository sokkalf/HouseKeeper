require 'chronic'
require 'securerandom'
require 'yaml'

require 'util/logging'
require 'util/persistence'
require 'util/scheduling'
require 'util/proc'
require 'util/hash'
require 'util/datashipper'

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
    logger.debug "Refreshing Yr data every #{yr_refresh}"
    scheduler.every yr_refresh do
      temperature = YrTemperature.get_reading
      CachedYrTemperature.set_temperature(temperature)
      temperature.save
    end

    datashipper_refresh = config['datashipper_refresh'] ||= '30m'
    datashipper_url = config['datashipper_url'] ||= 'http://localhost:5001/store'
    logger.debug "Shipping data to secondary storage every #{datashipper_refresh}"
    scheduler.every datashipper_refresh do
      logger.debug 'Fetching temperature data for shipping to external storage'
      temperatures = []
      all_temps = Temperature.find_all
      if all_temps
        all_temps.each do |temperature_reading, source, timestamp|
          temperatures << Temperature.new(temperature_reading, source, timestamp)
        end
        DataShipper.ship_data(datashipper_url, temperatures)
      else
        logger.debug 'Skipping  - No data.'
      end
    end

    inside_temperature_refresh = config['inside_temperature_refresh'] ||= '10m'
    outside_temperature_refresh = config['outside_temperature_refresh'] ||= '10m'

    scheduler.every inside_temperature_refresh do
      temperature = InsideTemperature.get_reading
      unless temperature.instance_of?(ErrorMessage)
        temperature.save
      end
    end

    scheduler.every outside_temperature_refresh do
      temperature = OutsideTemperature.get_reading
      unless temperature.instance_of?(ErrorMessage)
        temperature.save
      end
    end


    Schedule.find_all_schedules.each do |sched|
      if sched.type != 'recurring'
        if Chronic.parse(sched.timestamp) > Time.now
            action = self.get_action(sched.action, sched.device.id)
            unless action.instance_of?(Proc)
              action = nil
            end
            if action != nil
              action.name = sched.action
              schedule(sched.device, action, sched.timestamp, sched.uuid)
            end
        else
          Schedule.delete_by_uuid(sched.uuid)
        end
      else
        action = self.get_action(sched.action, sched.device.id)
        unless action.instance_of?(Proc)
          action = nil
        end
        if action != nil
          action.name = sched.action
          schedule_recurring(sched.device, action, sched.timestamp, sched.uuid)
        end
      end
    end

  end

  def get_action(request, id)
    case request
      when 'online'
        return Proc.new{self.online_device(id)}
      when 'offline'
        return Proc.new{self.offline_device(id)}
      when 'toggle'
        return Proc.new{self.toggle_device(id)}
      else
        status 400
        return ErrorMessage.new(400, 'Unknown action "' + request + '"')
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
    unless device.instance_of?(Device)
      return device
    end
    parsed_timestamp = Chronic.parse(timestamp)
    logger.info('Scheduling device ' + device.id + ' (' + device.name + ') for ' + action.name + ' at ' + parsed_timestamp.to_s)
    uuid = uuid != nil ? uuid : SecureRandom.uuid
    schedule = Schedule.new(device, parsed_timestamp.to_s, action.name, nil, uuid, 'regular')
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
    if Schedule.find_by_uuid(schedule.uuid) == nil # don't re-save when re-scheduling events stored in database
      schedule.save
    end
    schedule
  end

  def schedule_recurring(device, action, timestamp, uuid)
    unless device.instance_of?(Device)
      return device
    end
    logger.info('Scheduling recurring task: device ' + device.id + ' (' + device.name + ') for ' + action.name + ' every ' + timestamp.to_s)
    uuid = uuid != nil ? uuid : SecureRandom.uuid
    schedule = Schedule.new(device, timestamp.to_s, action.name, nil, uuid, 'recurring')
    job = scheduler.every timestamp do
      logger.info('Running recurring action...')
      action.call
    end
    schedule.job = job
    @schedules[job.job_id] = schedule
    @schedules_uuid[schedule.uuid] = job.job_id
    if Schedule.find_by_uuid(schedule.uuid) == nil # don't re-save when re-scheduling events stored in database
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
    @schedules.each do |_, v|
      sched_list << v
    end
    sched_list
  end
end