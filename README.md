fan-controller
==============

Controll the rotation speed of the computer fan (or fans) based on the temperature
sensors. Should work only on linux systems that provide files (in /sys/class/hwmon) to
get/set temperatures, fan rotation speeds and fan pwm values.

This is not ready for public use since everything is to be configured in the main ruby
script `fan.rb`.

The fan rotation speed is set by modifying the pwm value until the desired rotation speed
is reached. The pwm value is modified in large steps if the fan rotation speed differs for
more than 150 rpm and only in small steps for smaller differences. This eleminates the
need to calibrate the settings to specific fans or pwm controllers. The only downside is
that it may take soem time to bring the fan to the desired rotation speed. The desired
rotation speed is calculated by a custom function based on temperatures measured by hwmon
sensors. This function is just ruby code.
