$LOAD_PATH.unshift File.dirname(__FILE__)
require 'sinatra'
require 'json'

require 'tell_stick_controller'

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
    class Proc
      # redefine Proc to include name field
      # (used for logging what type of task is scheduled)
      attr_accessor :name
    end
    req = JSON.parse(request.body.read.to_s)
    if req['action'] != nil
      scheduled = req['timestamp'] != nil
      case req['action']
        when 'online'
          action = Proc.new{ts.online_device(id)}
        when 'offline'
          action = Proc.new{ts.offline_device(id)}
        when 'toggle'
          action = Proc.new{ts.toggle_device(id)}
        else
          status 400
          return ErrorMessage.new(400, 'Unknown action "' + req['action'] + '"')
      end
      action.name = req['action']
      if scheduled
        device = ts.schedule(ts.show_device(id), action, req['timestamp'])
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
    e.backtrace
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