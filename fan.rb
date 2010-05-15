#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'thread'


def log(text)
  puts("%s %s" % [ Time.now, text ])
end

def read_pwm(input)
  return File.read(input).split.first.to_i
end

def write_pwm(input, value)
  File.open(input, "w") do |io|
    io.write(value)
  end
end

def set_fan_rpm(options)
  curr_pwm = read_pwm(options[:pwm])
  curr_rpm = [1, read_rpm(options[:fan])].max
  diff_rpm = (curr_rpm - options[:target]).abs
  factor   = [0.85,
              options[:target].to_f / curr_rpm,
              1.15].sort[1]
  new_pwm  = (curr_pwm * factor).to_i

  if 10 < diff_rpm
    log("%s %4d rpm (%3d) -> %4d rpm (%3d)" % \
        [ options[:name],
          curr_rpm, curr_pwm,
          options[:target], new_pwm ])

    write_pwm(options[:pwm] + "_enable", 1)
    write_pwm(options[:pwm], new_pwm)
  end
end

def set_fan_speed(options)
  temp = options[:temp].map { |t| read_temperature(t) }
  rpm  = options[:func].call(*temp)

  set_fan_rpm(:name   => options[:name],
              :fan    => options[:fan],
              :pwm    => options[:pwm],
              :target => rpm)
end


class Sensor
  attr_accessor :samples
  attr_accessor :values


  def initialize(options = {})
    options = { :samples => 5 }.merge(options)

    @semaphore = Mutex.new

    self.samples = options[:samples]
    self.values  = []
  end

  def read
    nil
  end

  def update
    @semaphore.synchronize do
      self.values.shift while self.values.size >= self.samples
      self.values.push(self.read)
    end
  end

  def value
    value = nil

    @semaphore.synchronize do
      value = self.values.inject(:+) / self.values.size unless self.values.empty?
    end

    value
  end
end


class FileInputSensor < Sensor
  attr_accessor :filename

  def initialize(options = {})
    options = { :filename => nil }.merge(options)

    super(options)

    self.filename = options[:filename]
  end

  def read
    File.read(self.filename)
  end
end


class FanSensor < FileInputSensor
  def read
    super().split.first.to_i
  end
end


class TemperatureSensor < FileInputSensor
  def read
    super().split.first.to_i / 1000.0
  end
end


class FanController
  attr_accessor :filename
  attr_accessor :function

  def initialize(options = {})
    options = {
      :filename => nil,
      :function => lambda { nil },
    }.merge(options)

    self.filename = options[:filename]
    self.function = options[:function]
  end

  def set_fan_speed
  end
end


if __FILE__ == $0
  begin
    SENSOR_DIR = '/sys/devices/platform/w83627ehf.656'

    sensors = {
      :fan_cpu => FanSensor.new(:filename => File.join(SENSOR_DIR, 'fan2_input'),
                                :samples  => 5),
      :fan_system => FanSensor.new(:filename => File.join(SENSOR_DIR, 'fan1_input'),
                                   :samples  => 5),
      :temp_cpu => TemperatureSensor.new(:filename => File.join(SENSOR_DIR, 'temp2_input'),
                                         :samples => 3),
      :temp_cpu_thermistor => TemperatureSensor.new(:filename => File.join(SENSOR_DIR, 'temp3_input'),
                                                    :samples => 3),
      :temp_system => TemperatureSensor.new(:filename => File.join(SENSOR_DIR, 'temp1_input'),
                                            :samples => 3),
    }

    controllers = {
      :cpu => FanController.new(:filename => File.join(SENSOR_DIR, 'pwm2'),
                                :function => lambda { [ 500,
                                                        (0.1 * sensors[:temp_system].value +
                                                         0.6 * sensors[:temp_cpu].value +
                                                         0.3 * sensors[:temp_cpu_thermistor].value) * 40 - 1000
                                                      ].max } ),
      :power_supply => FanController.new(:filename => File.join(SENSOR_DIR, 'pwm4'),
                                         :function => lambda { [ 500,
                                                                 (0.8 * sensors[:temp_system].value +
                                                                  0.1 * sensors[:temp_cpu].value +
                                                                  0.1 * sensors[:temp_cpu_thermistor].value) * 45 - 1050
                                                               ].max } ),
    }

    threads = [ Thread.new {
                  loop {
                    sensors.each_pair { |sym, sensor| sensor.update }
                    sleep 2
                  }
                },
                Thread.new {
                  loop {
                    controllers.each_pair { |sym, controller| controller.set_fan_speed }
                    sleep 10
                  }
                }, ]

    threads.each { |t| t.join }
  rescue Interrupt
    log("Interrupted.")
  end
end
