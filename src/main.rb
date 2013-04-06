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

# TODO: don't use GET for these..
get '/online/:id' do |id|
  content_type :json
  ts.online_device(id).to_json
end

get '/offline/:id' do |id|
  content_type :json
  ts.offline_device(id).to_json
end

get '/toggle/:id' do |id|
  content_type :json
  ts.toggle_device(id).to_json
end