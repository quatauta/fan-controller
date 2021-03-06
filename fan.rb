#!/usr/bin/env ruby
# frozen_string_literal: true

# Base-class to store sensor values in a ring-buffer.
#
# @abstract Subclass and override {#read} to implement a sensor
class Sensor
  # The number of senor values stored in {#values}
  attr_accessor :samples

  # The ring-buffer to store the sensor values
  attr_accessor :values

  # Create a new +Sensor+
  #
  # @option [Integer] :samples (5) the number of sensor values to store in the ring-buffer
  def initialize(samples: 5)
    @semaphore = Mutex.new

    self.samples = samples
    self.values  = []
  end

  # Called by update to read a single value from the sensor. This must be implemented by a
  # sub-class to actually get the sensor value.
  #
  # @abstract
  # @return [Object] the value read from the sensor
  def read
    nil
  end

  # Read the sensor value and put it into the ring-buffer {#values}. Maintains the size of
  # the ring-buffer.
  #
  # @return [nil]
  def update
    @semaphore.synchronize do
      values.shift while values.size >= samples
      values.push(read)
    end
  end

  # Get the average value of the sensor values stored in the ring-buffer {#values}.
  #
  # @return [Numeric] average value from ring-buffer or +nil+ if buffer is empty
  def value
    value = nil

    @semaphore.synchronize do
      value = values.inject(:+) / values.size unless values.empty?
    end

    value
  end
end

# Reads a single sensor value from a file.
class FileInputSensor < Sensor
  # The name of the file to read the sensor value from
  attr_accessor :filename

  # Create a new {FileInputSensor} object
  #
  # @option opts [String] :filename The name of the file to read
  def initialize(samples: 5, filename:)
    super(samples: samples)

    self.filename = filename
  end

  # Read the content of the file
  def read
    File.read(filename)
  end
end

# Reads fan rotation speed
class FanSensor < FileInputSensor
  # Parse the file read by {FileInputSensor#read} as integer to a fan rotation speed
  #
  # @return [Integer] the fan's rotation speed
  def read
    super.to_i
  end
end

# Reads the temperature of a mainboard temperature sensor
class TemperatureSensor < FileInputSensor
  # Parse the file read by {FileInputSensor#read} as float to a temperature
  #
  # @return [Float] the temperature
  def read
    super.to_i / 1000.0
  end
end

# Set the rotation speed of a fan according to a supplied function
class FanController
  # The {FanSensor} to read the fan's rotations speed
  # @return [FanSensor]
  attr_accessor :fan_sensor

  # The file to read/write the PWM value from/to
  # @return [String]
  attr_accessor :filename

  attr_accessor :filename_pwn_enable

  # The +Proc+ that calculates the rotation speed of the fan
  # @return [Proc]
  attr_accessor :function

  # The name of the fan. Only used in the logging output prodcued by {#set_fan_speed}
  # @return [String]
  attr_accessor :name

  # Create a new +FanController+ object
  #
  # @option opts [String] :name ("n/a") the name of the controlled fan
  # @option opts [FanSensor] :fan_sensor the {FanSensor} to read the rotation speed from
  # @option opts [String] :filename the file to read/write the PWM value from/to
  # @option opts [Proc] :function (lambda { nil }) the function that calculates the fan's rotation speed
  def initialize(name: "n/a", fan_sensor:, filename:, function: lambda { nil })
    self.fan_sensor = fan_sensor
    self.filename   = filename
    self.function   = function
    self.name       = name

    self.filename_pwn_enable = format("%s_enable", self.filename)
  end

  # Read the fan's PWM value from {#filename}
  #
  # @return [Integer] the PWM value
  def pwm
    File.read(filename).split.first.to_i
  end

  # Write the new fan's PWM value to +filename+ and enable the PWM feature
  #
  # @param [Integer] value the new PWM value of the fan, limited to values 0..255
  # @return [nil]
  def pwm=(value)
    File.open(filename_pwn_enable, "w") do |io|
      io.write(1)
    end

    File.open(filename, "w") do |io|
      io.write(value.to_i.clamp(0, 255))
    end
  end

  # Set the speed of the fan. The new rotation speed is returned by {#function}. The PWM
  # value gets modifed according to the difference of the current speed and the new speed.
  #
  # @return [Integer] the rotation speed the returned from {#function}
  # @see #speed_diff_to_pwm_diff
  def set_fan_speed
    current_pwm   = pwm
    current_speed = fan_sensor.value.to_i
    target_speed  = function.call.to_i
    pwm_diff      = speed_diff_to_pwm_diff(target_speed - current_speed)

    if pwm_diff != 0
      # log("%s: %d rpm to %d rpm, changing %s by %d." % \
      #     [ self.name,
      #       current_speed,
      #       target_speed,
      #       File.basename(self.filename),
      #       pwm_diff ])
      self.pwm = current_pwm + pwm_diff
    end

    target_speed
  end

  # Get the PWM difference for the given difference of the fan's rotation speed. For
  # differences less or equal than 10 rounds per minute, the PWM value is not changed. At
  # a difference of 11 to 50 rpm, the PWM value is changed by 1. At 51 to 150 rpm, PWM is
  # change by 3. For larger differences, the PWM value is changed by 10.
  #
  # The fan should slowly read the targed speed that way.
  #
  # @param [Numeric] speed_diff the rotation speed difference
  # @return [Integer] the PWM value difference
  def speed_diff_to_pwm_diff(speed_diff)
    inf = 1.0 / 0.0

    case speed_diff
      when (151..inf) then 10
      when (51..150) then 3
      when (11..50) then 1
      when (-10..10) then 0
      when (-50..-11) then -1
      when (-150..-51) then -3
      when (-inf..-151) then -10
      else 0
    end
  end
end

# Print the text prefixed by the current date and time.
#
# If an Exception is given, the thread-local variable +:name+ (or +Thread#to_s+) and the
# backtrace is logged.
#
# @param [String] msg the text or Exception to print
# @return [nil]
def log(msg)
  if msg.is_a? Exception
    log(format("Exception in thread %s\n  %s\n  %s", Thread.current[:name] || Thread.current.to_s, msg.inspect, msg.backtrace.join("\n  ")))
  else
    $stdout.puts(format("%s %s", Time.now, msg))
    $stdout.flush
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    SENSOR_DIR = "/sys/devices/platform"

    sensors = {
      fan_cpu: FanSensor.new(filename: File.join(SENSOR_DIR, "it87.656", "hwmon", "hwmon0", "fan1_input"), samples: 5),
      fan_psu: FanSensor.new(filename: File.join(SENSOR_DIR, "it87.656", "hwmon", "hwmon0", "fan2_input"), samples: 5),
      temp_cpu: TemperatureSensor.new(filename: File.join(SENSOR_DIR, "coretemp.0", "hwmon", "hwmon1", "temp5_input"), samples: 3),
      temp_system: TemperatureSensor.new(filename: File.join(SENSOR_DIR, "it87.656", "hwmon", "hwmon0", "temp2_input"), samples: 3),
    }

    controllers = {
      cpu: FanController.new(name: "CPU",
                             filename: File.join(SENSOR_DIR, "it87.656", "hwmon", "hwmon0", "pwm3"),
                             fan_sensor: sensors[:fan_cpu],
                             function: lambda {
                               [400,
                                (0.5 * sensors[:temp_system].value +
                                 0.5 * sensors[:temp_cpu].value) * 42 - 1000,].max
                             }),
      power_supply: FanController.new(name: "PSU",
                                      filename: File.join(SENSOR_DIR, "it87.656", "hwmon", "hwmon0", "pwm2"),
                                      fan_sensor: sensors[:fan_psu],
                                      function: lambda {
                                        [400,
                                         (0.7 * sensors[:temp_system].value +
                                          0.3 * sensors[:temp_cpu].value) * 46 - 1050,].max
                                      }),
    }

    log("Starting ...")

    Thread.abort_on_exception = true

    Thread.new do
      Thread.current[:name] = "GC"
      loop {
        GC.start
        sleep(300)
      }
    end

    Thread.new do
      Thread.current[:name] = "Sensors"
      loop {
        sensors.each_pair { |sym, sensor| sensor.update }
        sleep(3)
      }
    end

    log("Collecting sensor values for 10 seconds ...")
    sleep(10)

    log("Controlling fan speed.")
    Thread.current[:name] = "Controllers"
    loop {
      controllers.each_pair { |sym, controller| controller.set_fan_speed }
      sleep(6)
    }
  rescue => error
    log(error)
  end
end
