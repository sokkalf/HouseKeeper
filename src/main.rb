$LOAD_PATH.unshift File.dirname(__FILE__)
require 'sinatra'
require 'json'

require 'util/proc'
require 'tell_stick_controller'
require 'errormessage'
require 'device'
require 'schedule'
require 'temperature'

configure do
  set :bind, '0.0.0.0'
  mime_type :json, 'application/json'
end

ts = TellStickController.new

get '/' do
  'Welcome to HouseKeeper!'
end

get '/devices' do
  content_type :json
  ts.list_devices.to_json
end

get '/device/:id' do |id|
  content_type :json
  device = ts.show_device(id)
  if device.instance_of?(ErrorMessage)
    status device.error
  end
  device.to_json
end



# do an instant action, or if "timestamp" is given, set a scheduled task
put '/device/:id' do |id|
  content_type :json
  begin
    req = JSON.parse(request.body.read.to_s)
    if req['action'] != nil
      scheduled = req['timestamp'] != nil
      action = ts.get_action(req['action'], id)
      action.name = req['action']
      if scheduled
        device = ts.schedule(ts.show_device(id), action, req['timestamp'], nil)
      else
        device = action.call
      end
      if device.instance_of?(ErrorMessage)
        status device.error
      end
      device.to_json
    else
      return ErrorMessage.new(400, 'Need action and id parameters').to_json
    end
  rescue Exception => e
    status 400
    'Malformed request'
  end
end

get '/schedules' do
  content_type :json
  ts.list_scheduled_tasks.to_json
end

get '/schedule/:id' do |id|
  content_type :json
  ts.list_scheduled_tasks[id].to_json
end

delete '/schedule/:id' do |id|
  content_type :json
  ts.unschedule_by_uuid(id).to_json
end

put '/schedule/' do
  content_type :json
  begin
    req = JSON.parse(request.body.read.to_s)
    if req['action'] != nil && req['timestamp'] != nil && req['device'] != nil
      id = req['device']
      recurring = req['recurring'] != nil
      action = ts.get_action(req['action'], id)
      action.name = req['action']
      if recurring
        device = ts.schedule_recurring(ts.show_device(id), action, req['timestamp'], nil)
      else
        device = ts.schedule(ts.show_device(id), action, req['timestamp'], nil)
      end
      if device.instance_of?(ErrorMessage)
        status device.error
      end
      device.to_json
    else
      return ErrorMessage.new(400, 'Need action and id parameters').to_json
    end
  rescue Exception => e
    status 400
    'Malformed request'
  end
end

get '/temperature' do
  content_type :json
  YrTemperature.get_reading.to_json
end
