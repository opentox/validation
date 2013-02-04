require 'rubygems'
#gem "opentox-ruby"
[ 'sinatra', 'sinatra/url_for', 'ohm', 'benchmark' ].each do |lib|
  require lib
end

require "./test/test_application.rb"
require "./report/report_application.rb"
require "./validation/validation_application.rb"




