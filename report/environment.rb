['rubygems', 'logger', 'fileutils', 'sinatra', 'sinatra/url_for', 'rest_client', 
  'yaml', 'fileutils', 'mime/types', 'abbrev', 
  'rexml/document',  'ruby-plot' ].each do |g|
    require g
end

module Reports

  def self.r_util
    @@r_util = OpenTox::RUtil.new unless defined?@@r_util and @@r_util
    @@r_util
  end
  
  def self.quit_r
    if defined?@@r_util and @@r_util
      @@r_util.quit_r
      @@r_util = nil
    end
  end
    
end

require "./lib/ot_predictions.rb"
require "./lib/ohm_util.rb"

require "./report/plot_factory.rb"
require "./report/xml_report.rb"
require "./report/xml_report_util.rb"
require "./report/report_persistance.rb"
require "./report/report_content.rb"
require "./report/report_factory.rb"
require "./report/report_service.rb"
require "./report/report_format.rb"
require "./report/validation_access.rb"
require "./report/validation_data.rb"
require "./report/util.rb"
require "./report/statistical_test.rb"

ICON_ERROR = File.join($validation[:uri],"resources/error.png")
ICON_OK = File.join($validation[:uri],"resources/ok.png")



