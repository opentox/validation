
['rubygems', 'logger', 'fileutils', 'sinatra', 'sinatra/url_for', 'rest_client', 
  'yaml', 'opentox-ruby-api-wrapper', 'fileutils', 'mime/types', 'abbrev', 
  'rexml/document', 'active_record', 'ar-extensions', 'ruby-plot'].each do |g|
    require g
end
gem 'ruby-plot', '= 0.0.2'

unless ActiveRecord::Base.connected?
  ActiveRecord::Base.establish_connection(  
     :adapter => CONFIG[:database][:adapter],
     :host => CONFIG[:database][:host],
     :database => CONFIG[:database][:database],
     :username => CONFIG[:database][:username],
     :password => CONFIG[:database][:password]
  )
  ActiveRecord::Base.logger = Logger.new("/dev/null")
end

module Reports
end

require "lib/rdf_provider.rb"

require "report/plot_factory.rb"
require "report/xml_report.rb"
require "report/xml_report_util.rb"
require "report/report_persistance.rb"
require "report/report_factory.rb"
require "report/report_service.rb"
require "report/report_format.rb"
require "report/validation_access.rb"
require "report/validation_data.rb"
require "report/prediction_util.rb"
require "report/util.rb"
require "report/external/mimeparse.rb"

require "lib/ot_predictions.rb"



