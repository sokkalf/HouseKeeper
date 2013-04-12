require 'util/persistence'

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