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

get '/list' do
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

put '/device/:id' do |id|
  begin
    req = JSON.parse(request.body.read.to_s)
    if req['action'] != nil
      case req['action']
        when 'online'
          device = ts.online_device(id)
        when 'offline'
          device = ts.offline_device(id)
        when 'toggle'
          device = ts.toggle_device(id)
        else
          device = ErrorMessage.new(400, 'Unknown action "' + req['action'] + '"')
      end
      if device.instance_of?(ErrorMessage)
        status device.error
      end
      return device.to_json
    else
      return ErrorMessage.new(400, 'Need action and id parameters').to_json
    end
  rescue Exception => e
    status 400
    'Malformed request'
  end
end