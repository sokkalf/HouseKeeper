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
  content_type :json
  ts.list_devices.to_json
end

get '/detail/:id' do |id|
  content_type :json
  device = ts.show_device(id)
  if device.instance_of?(ErrorMessage)
    status device.error
  end
  device.to_json
end

# TODO: don't use GET for these..
get '/online/:id' do |id|
  content_type :json
  device = ts.online_device(id)
  if device.instance_of?(ErrorMessage)
    status device.error
  end
  device.to_json
end

get '/offline/:id' do |id|
  content_type :json
  device = ts.offline_device(id)
  if device.instance_of?(ErrorMessage)
    status device.error
  end
  device.to_json
end

get '/toggle/:id' do |id|
  content_type :json
  device = ts.toggle_device(id)
  if device.instance_of?(ErrorMessage)
    status device.error
  end
  device.to_json
end