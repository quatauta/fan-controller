# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "hwmon_fan_controller"
  spec.version       = "0.1"
  spec.authors       = "Daniel Schömer"
  spec.email         = "daniel.schoemer@gmx.net"

  spec.summary       = "Control Linux hwmon fan speed based on temperature sensors"
  spec.description   = "Based on temperature sensor values, the speed/rpm of CPU/system fan(s) is controlled. You define a function to return the speed/rpm based on temperatures. The fan controller maintains the fan speed by updating the PWM."
  spec.homepage      = "https://github.com/quatauta/#{spec.name}"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.3.0"

  spec.add_runtime_dependency "symbolic"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "bundler-audit"
  spec.add_development_dependency "flog"
  spec.add_development_dependency "cucumber", ">= 0.1.8"
  spec.add_development_dependency "fuubar"
  spec.add_development_dependency "metric_fu", ">= 1.5"
  spec.add_development_dependency "rake", ">= 0.8.3"
  spec.add_development_dependency "rdoc", ">= 2.4"
  spec.add_development_dependency "rspec", ">= 3"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubinjam"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "standard"
  spec.add_development_dependency "yard", ">= 0.9.5"
end
