require 'rubygems'
#gem "opentox-ruby"
[ 'sinatra', 'sinatra/url_for', 'ohm', 'benchmark' ].each do |lib|
  require lib
end

class Sinatra::Base
  helpers Sinatra::UrlForHelper
end

#unless(defined? LOGGER)
  #LOGGER = Logger.new(STDOUT)
  #LOGGER.datetime_format = "%Y-%m-%d %H:%M:%S "
#end

require "./test/test_application.rb"
require "./report/report_application.rb"
#require "./reach_reports/reach_application.rb"
require "./validation/validation_application.rb"




