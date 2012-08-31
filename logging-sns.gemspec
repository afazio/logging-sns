# -*- encoding: utf-8; mode: ruby -*-
require File.expand_path('../lib/logging-sns/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Alfred J. Fazio"]
  gem.email         = ["alfred.fazio@gmail.com"]
  gem.description   = %q{AWS Simple Notification Service (SNS) appender for Logging}
  gem.summary       = %q{AWS Simple Notification Service (SNS) appender for Logging}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "logging-sns"
  gem.require_paths = ["lib"]
  gem.version       = Logging::Appenders::SNS::VERSION

  gem.add_dependency = 'aws-sdk'
  gem.add_dependency = 'json'
end
