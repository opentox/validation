require 'rubygems'
#gem "opentox-ruby"
[ 'sinatra', 'ohm', 'benchmark' ].each do |lib|
  require lib
end

require "./test/test_application.rb"
require "./report/report_application.rb"
require "./validation/validation_application.rb"




