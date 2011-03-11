
require "rubygems"
require "sinatra"
before {
  request.env['HTTP_HOST']="local-ot/validation"
  request.env["REQUEST_URI"]=request.env["PATH_INFO"]
}

require "uri"
require "yaml"
ENV['RACK_ENV'] = 'test'
require 'application.rb'
require 'test/unit'
require 'rack/test'
require 'lib/test_util.rb'
require 'test/test_examples.rb'

LOGGER = OTLogger.new(STDOUT)
LOGGER.datetime_format = "%Y-%m-%d %H:%M:%S "
LOGGER.formatter = Logger::Formatter.new

if AA_SERVER
  #TEST_USER = "mgtest"
  #TEST_PW = "mgpasswd"
  TEST_USER = "guest"
  TEST_PW = "guest"
  SUBJECTID = OpenTox::Authorization.authenticate(TEST_USER,TEST_PW)
  raise "could not log in" unless SUBJECTID
  puts "logged in: "+SUBJECTID.to_s
else
  puts "AA disabled"
  SUBJECTID = nil
end

#Rack::Test::DEFAULT_HOST = "local-ot/validation"
module Sinatra
  module UrlForHelper
    BASE = "http://local-ot/validation"
   def url_for url_fragment, mode=:path_only
      case mode
      when :path_only
        raise "not impl"
      when :full
      end
      "#{BASE}#{url_fragment}"
    end
  end
  set :raise_errors, false
  set :show_exceptions, false
end


#DataMapper::Model.raise_on_save_failure = true
#
#class TestResourceX
#    include DataMapper::Resource
#    
#    property :id, Serial
#    
#    has 1, :test_resource
#end
#
#class DataMapper::Associations::ManyToOne::Relationship
#  def get_parent_model
#    @parent_model
#  end
#end
#
#class TestResource
#    include DataMapper::Resource
#    
#    property :id, Serial
#    property :time, DateTime
#    property :body, Text
#    
#    def self.info
#      relationships.each do |k,v|
#        puts k
#        puts v.inspect
#        puts v.get_parent_model
#        
#      end
#    end
#    #validates_format_of :time
#    #validates_length_of :body, :minimum => 1000
#    
#    belongs_to :test_resource_x
#end
#
#TestResourceX.auto_upgrade!
#TestResource.auto_upgrade!

class ReachTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include Lib::TestUtil
  
  def app
    Sinatra::Application
  end

  def test_it
    
    begin
    
   # delete '/reach_report/QMRF/3'
   # puts last_response.body
    
    #exit
#    testResource = TestResource.new
#    
#    TestResource.info
#    exit
    
#    p = nil
#    #puts TestResource.properties.inspect 
#    TestResource.properties.each do |pp|
#      p = pp if pp.name==:time
#    end
#    #puts p
#    val = "no time" #DateTime.new
#    testResource.time = val
#    #puts p.valid?(val)
#    
#    #puts "test restource: "+testResource.valid?.to_s
#    
#    #puts testResource.time.to_s + " " + testResource.time.class.to_s
#    begin
#      testResource.save
#    rescue DataMapper::SaveFailureError => e
#      puts e.message
#      puts e.resource.errors.inspect
#    end
#    exit
  
    #$test_case = self

#    #file = File.new("qmrf-report.xml")
#    file = File.new("/home/martin/win/home/test2.xml")
#    raise "File not found: "+file.path.to_s unless File.exist?(file.path)
#    data = File.read(file.path)
#    #puts "data found "+data.to_s[0..1000]
#    puts OpenTox::RestClientWrapper.post("http://local-ot/validation/reach_report/qmrf/20",{:content_type => "application/qmrf-xml"},data).to_s.chomp

#    post "/reach_report/qmrf/8"
#    puts last_response.body
    
    #model_uri = "http://ambit.uni-plovdiv.bg:8080/ambit2/model/173393"
    
    #model_uri = "http://local-ot/majority/class/model/58"
    
    
    #model_uri = "http://local-ot/model/104"
    model_uri = "http://local-ot/majority/class/model/125"
    
    
#    m = OpenTox::Model::Generic.find(model_uri)
#    puts m.metadata[OT.algorithm] if m
#    a = OpenTox::Algorithm::Generic.find(m.metadata[OT.algorithm])
#    puts a.metadata.inspect
#    exit
    
    puts SUBJECTID

#    model_uri = "http://local-ot/model/1"
    #http://local-ot/majority/class/model/15
    #model_uri = "http://local-ot/majority/class/model/15"
   # model_uri = "http://local-ot/majority/class/model/91"
    #model_uri = "http://apps.ideaconsult.net:8080/ambit2/model/2"
    post '/reach_report/qmrf',{:model_uri=>model_uri, :subjectid => SUBJECTID} #http://local-ot/model/1"
    ##post '/reach_report/qprf',:compound_uri=>"http://local-ot/compound/XYZ"
    uri = last_response.body
    puts "task: "+uri.to_s
    uri = Lib::TestUtil.wait_for_task(uri)
    if uri
      id = uri.split("/")[-1]
      puts uri
    end

#    id = "8"

    #get '/reach_report/qmrf'
    #puts last_response.body
    
#    get '/reach_report/qmrf/'+id.to_s,nil,'HTTP_ACCEPT'=>"application/x-yaml"
#    puts "YAML"
#    puts last_response.body
    
#     get '/reach_report/qmrf/'+id.to_s,nil,'HTTP_ACCEPT'=>"application/rdf+xml"
#    puts "RDF"
#    puts last_response.body

    #get '/reach_report/qmrf/'+id,nil,'HTTP_ACCEPT' => "application/qmrf-xml"
    #puts "XML"
    #puts last_response.body
    
    
    #r = ReachReports::QmrfReport.find_like( :QSAR_title => "Hamster")
    #puts r.collect{|rr| "report with id:"+rr.id.to_s}.inspect
    
    #File.new("/home/martin/tmp/qmr_rep_del_me.xml","w").puts last_response.body
    #File.new("/home/martin/win/home/qmr_rep_del_me.xml","w").puts last_response.body
    #File.new("/home/martin/info_home/.public_html/qmr_rep_del_me.xml","w").puts last_response.body
    
    rescue => ex
      rep = OpenTox::ErrorReport.create(ex, "")
      puts rep.to_yaml
    end
      
      
  end
end


#    query = <<EOF
#PREFIX ot:<http://www.opentox.org/api/1.1#>
#PREFIX rdf:<http://www.w3.org/1999/02/22-rdf-syntax-ns#>
#select ?model  
#where {
#?model rdf:type ot:Model
#}
#EOF
#    puts OpenTox::RestClientWrapper.post("http://apps.ideaconsult.net:8080/ontology/",{:accept => "application/rdf+xml", :query => query}) 
#    exit
 
#class Person
#    include DataMapper::Resource
#    
#    property :id, Serial
#    
#    has 1, :profile
#    has 1, :profile2
#  end
#  
#  class Profile
#    include DataMapper::Resource
#    
#    property :id, Serial
#    property :val, Text
#    
#    belongs_to :person
#  end
#  
#    class Profile2
#    include DataMapper::Resource
#    
#    property :id, Serial
#    property :val, Text
#    
#    belongs_to :person
#  end
# 
#Person.auto_upgrade!
#Profile.auto_upgrade!
#Profile2.auto_upgrade!
# 
# A.auto_upgrade!
# ValTest.auto_upgrade!
 #A.auto_migrate!
 #ValTest.auto_migrate!
 
# class ReachTest < Test::Unit::TestCase
#  include Rack::Test::Methods
#  include Lib::TestUtil
#
#  
#  def app
#    Sinatra::Application
#  end
#
#  def test_datamapper
#    
#     # Assigning a resource to a one-to-one relationship
# puts Person.all.collect{|v| v.id}.inspect
# 
# person  = Person.create
# person.profile = Profile.new
# person.profile2 = Profile2.new
# person.profile2.val = "bla"
# person.save
# 
# p = Person.get(11)
## puts p.profile2
# puts p.profile2.val

