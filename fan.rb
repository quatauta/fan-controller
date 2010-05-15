#!/usr/bin/env ruby
# -*- coding: utf-8 -*-


DIR  = '/sys/devices/platform/w83627ehf.656'
CONF = {
  :cpu => {
    :fan     => File.join(DIR, 'fan2_input'),
    :pwm     => File.join(DIR, 'pwm2'),
    :temp    => [ File.join(DIR, 'temp1_input'),
                  File.join(DIR, 'temp2_input'),
                  File.join(DIR, 'temp3_input') ],
    :func    => lambda { |sys, cpu, cpu_mb|
      [
       500,
       (0.1 * sys +
        0.6 * cpu +
        0.3 * cpu_mb) * 40 - 1000
      ].max
    },
  },
  :psu => {
    :fan     => File.join(DIR, 'fan1_input'),
    :pwm     => File.join(DIR, 'pwm4'),
    :temp    => [ File.join(DIR, 'temp1_input'),
                  File.join(DIR, 'temp2_input'),
                  File.join(DIR, 'temp3_input') ],
    :func    => lambda { |sys, cpu, cpu_mb|
      [
       500,
        (0.8 * sys +
         0.1 * cpu +
         0.1 * cpu_mb) * 45 - 1050
      ].max
    },
  },
}


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

def read_rpm(input)
  values = []

  (0..3).each do
    values << File.read(input).split.first.to_i
    sleep(1)
  end

  values.inject(:+) / values.size
end

def read_temperature(input)
  values = []

  (0..3).each do
    values << File.read(input).split.first.to_i / 1000.0
    sleep(1)
  end

  values.inject(:+) / values.size
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


if __FILE__ == $0
  begin
    log("Starting #{$0}")

    threads = []

    CONF.each_pair do |fan, fan_options|
      threads << Thread.new(fan, fan_options) do |f, o|
        loop do
          set_fan_speed({ :name => f }.merge(o))
          sleep(10)
        end
      end
    end

    threads.each { |t| t.join }

    log("Done")
  rescue Interrupt
    log("Interrupted")
  end
end
