class ErrorMessage
  attr_accessor :error, :message

  def initialize(error, message)
    @error = error
    @message = message
  end
  def to_json(*a)
    {
        :error => error,
        :message => message,
    }.to_json(*a)
  end
end

class Device
  attr_accessor :id, :name, :status

  def initialize(id, name, status)
    @id = id
    @name = name
    @status = status
  end

  def to_json(*a)
    {
        :id => @id,
        :name => @name,
        :status => @status,
        :error => @error,
    }.to_json(*a)
  end

  def online
    output = %x{tdtool --on #{@id}}
    if (output =~ /Success$/) != nil
      @status = 'ON'
    else
      class << self
        attr_accessor :error
      end
      self.error = ErrorMessage.new(502, 'Device not onlined')
    end
    self
  end

  def offline
    output = %x{tdtool --off #{@id}}
    if (output =~ /Success$/) != nil
      @status = 'OFF'
    else
      class << self
        attr_accessor :error
      end
      self.error = ErrorMessage.new(502, 'Device not offlined')
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

class TellStickController
  def list_devices
    output = %x{tdtool --list}
    lines = output.split("\n")
    lines.shift
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
    device != nil ? device : ErrorMessage.new(501, 'No such device: ' + id)
  end

  def online_device(id)
    device = list_devices[id]
    device != nil ? device.online : ErrorMessage.new(501, 'No such device: ' + id)
  end

  def offline_device(id)
    device = list_devices[id]
    device != nil ? device.offline : ErrorMessage.new(501, 'No such device: ' + id)
  end

  def toggle_device(id)
    device = list_devices[id]
    device != nil ? device.toggle : ErrorMessage.new(501, 'No such device: ' + id)
  end
end