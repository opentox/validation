
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
  TEST_USER = "mgtest"
  TEST_PW = "mgpasswd"
  #TEST_USER = "guest"
  #TEST_PW = "guest"
  SUBJECTID = OpenTox::Authorization.authenticate(TEST_USER,TEST_PW)
  raise "could not log in" unless SUBJECTID
  puts "logged in: "+SUBJECTID.to_s
else
  puts "AA disabled"
  SUBJECTID = nil
end

#Rack::Test::DEFAULT_HOST = "local-ot" #"/validation"
module Sinatra
  
  set :raise_errors, false
  set :show_exceptions, false

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
end


class ValidationTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include Lib::TestUtil
  
  def test_it
    begin
      $test_case = self
      
#    prediction_feature = "https://ambit.uni-plovdiv.bg:8443/ambit2/feature/26221"
#    puts OpenTox::Feature.find(prediction_feature).domain.inspect
#      exit

#      begin
#        #OpenTox::RestClientWrapper.get "http://local-ot/validation/runtime-error",{:accept => "application/rdf+xml"}
#        puts OpenTox::RestClientWrapper.post "http://opentox.ntua.gr:4000/model/0d8a9a27-3481-4450-bca1-d420a791de9d",
#          { :asdfasdf => "asdfasdf" } #{:dataset=>"http://apps.ideaconsult.net:8080/ambit2/dataset/54?max=2"},
#          { :accept => "text/uri-list", :subjectid => SUBJECTID } 
#        #puts OpenTox::RestClientWrapper.post "http://opentox.ntua.gr:4000/model/0d8a9a27-3481-4450-bca1-d420a791de9d",{},{:accept => "text/uri-list", :subjectid => "AQIC5wM2LY4SfcwUNX97nTvaSTdYJ+nTUqZsR0UitJ4+jlc=@AAJTSQACMDE=#"}
#      rescue => err
#        rep = OpenTox::ErrorReport.create(err, "")
#         puts rep.to_yaml
#      end  
        
        # "http://opentox.ntua.gr:4000/model/0d8a9a27-3481-4450-bca1-d420a791de9d"
      
#      get "/19999",nil,'HTTP_ACCEPT' => "text/html"
#      exit
#       
#      get "/234234232341",nil,'HTTP_ACCEPT' => "application/x-yaml"
#      puts last_response.body
##      
#      get "/crossvalidation/1",nil,'HTTP_ACCEPT' => "application/rdf+xml"
#      puts last_response.body
#      exit
      
  #    d = OpenTox::Dataset.find("http://ot-dev.in-silico.ch/dataset/307")
  #    puts d.compounds.inspect
  #    exit
      
      #get "?model=http://local-ot/model/1" 
  #    get "/crossvalidation/3/predictions"
  #    puts last_response.body
  
  #    post "/validate_datasets",{
  #      :test_dataset_uri=>"http://apps.deaconsult.net:8080/ambit2/dataset/R3924",
  #      :prediction_dataset_uri=>"http://apps.ideaconsult.net:8080/ambit2/dataset/R3924?feature_uris[]=http%3A%2F%2Fapps.ideaconsult.net%3A8080%2Fambit2%2Fmodel%2F52%2Fpredicted",
  #      #:test_target_dataset_uri=>"http://local-ot/dataset/202",
  #      :prediction_feature=>"http://apps.ideaconsult.net:8080/ambit2/feature/21715",
  #      :predicted_feature=>"http://apps.ideaconsult.net:8080/ambit2/feature/28944",
  #      :regression=>"true"}
  #      #:classification=>"true"}
  #    puts last_response.body
      
      #post "/crossvalidation/cleanup"
      #puts last_response.body
  
      #get "/crossvalidation/19/predictions",nil,'HTTP_ACCEPT' => "application/x-yaml" #/statistics"
  #    post "",:model_uri=>"http://local-ot/model/1",:test_dataset_uri=>"http://local-ot/dataset/3",
  #      :test_target_dataset_uri=>"http://local-ot/dataset/1"
  
  #    get "/crossvalidation/2",nil,'HTTP_ACCEPT' => "application/rdf+xml" 
     #puts last_response.body
     #exit

#    OpenTox::Crossvalidation.create( 
#      :dataset_uri=>"http://local-ot/dataset/1874", 
#      :algorithm_uri=>"http://local-ot/algorithm/lazar", 
#      :prediction_feature=>"http://local-ot/dataset/1874/feature/Hamster%20Carcinogenicity", 
#      :algorithm_params=>"feature_generation_uri=http://local-ot/algorithm/fminer/bbrc")

#http://local-ot/dataset/1878
      
      #get "/crossvalidation?model_uri=lazar"
  #    post "/test_validation",:select=>"6d" #,:report=>"yes,please"
      #puts last_response.body
      
  #    post "/validate_datasets",{
  #      :test_dataset_uri=>"http://local-ot/dataset/204",
  #      :prediction_dataset_uri=>"http://local-ot/dataset/206",
  #      :test_target_dataset_uri=>"http://local-ot/dataset/202",
  #      :prediction_feature=>"http://ot-dev.in-silico.ch/toxcreate/feature#IRIS%20unit%20risk",
  #      :predicted_feature=>"http://ot-dev.in-silico.ch/toxcreate/feature#IRIS%20unit%20risk_lazar_regression",
  #      :regression=>"true"}
  #      #:classification=>"true"}
  #    puts last_response.body
  
  #     post "/validate_datasets",{
  #      :test_dataset_uri=>"http://local-ot/dataset/89",
  #       :prediction_dataset_uri=>"http://local-ot/dataset/91",
  #       :test_target_dataset_uri=>"http://local-ot/dataset/87",
  #       :prediction_feature=>"http://local-ot/dataset/1/feature/hamster_carcinogenicity",
  #       :predicted_feature=>"",
  ##      :regression=>"true"}
  #       :classification=>"true"}
  #    puts last_response.body
  
      # m = OpenTox::Model::Generic.find("http://local-ot/model/1323333")
      # puts m.to_yaml
  
#     post "/validate_datasets",{
#         :test_dataset_uri=>"http://local-ot/dataset/390",
#         :prediction_dataset_uri=>"http://local-ot/dataset/392",
#         :test_target_dataset_uri=>"http://local-ot/dataset/388",
#         :prediction_feature=>"http://local-ot/dataset/388/feature/repdose_classification",
#         :model_uri=>"http://local-ot/model/31"}
#        #:regression=>"true"}
#  #       :classification=>"true"}
#      uri = last_response.body
#      val = wait_for_task(uri)
#      puts val
#      get "/"+val.split("/")[-1]

#     post "/validate_datasets",{
#         :test_dataset_uri=>"http://opentox.informatik.uni-freiburg.de/dataset/409",
#         :prediction_dataset_uri=>"http://opentox.informatik.uni-freiburg.de/dataset/410",
#         :test_target_dataset_uri=>"https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401560",
#         :prediction_feature=>"https://ambit.uni-plovdiv.bg:8443/ambit2/feature/22190",
#         :predicted_feature=>"https://ambit.uni-plovdiv.bg:8443/ambit2/feature/218304",
#         :regression=>"true",
#         :subjectid=>SUBJECTID}
#         #:model_uri=>"http://local-ot/model/31"}
#        #:regression=>"true"}
#  #       :classification=>"true"}
#      uri = last_response.body
#      val = wait_for_task(uri)
#      puts val
#      #get "/"+val.split("/")[-1]
     
     

     #ambit_service = "https://ambit.uni-plovdiv.bg:8443/ambit2"
      #https%3A%2F%2Fambit.uni-plovdiv.bg%3A8443%2Fambit2

#     post "/validate_datasets",{
#         :test_dataset_uri=>ambit_service+"/dataset/R401577?max=50",
#         :prediction_dataset_uri=>ambit_service+"/dataset/R401577?max=50&feature_uris[]="+CGI.escape(ambit_service)+"%2Fmodel%2F35194%2Fpredicted",
#         #:test_target_dataset_uri=>ambit_service+"/dataset/R401560",
#         :prediction_feature=>ambit_service+"/feature/26221",
#         :predicted_feature=>ambit_service+"/feature/218699",
#         :classification=>"true",
#         :subjectid=>SUBJECTID}
#         #:model_uri=>"http://local-ot/model/31"}
#        #:regression=>"true"}
#  #       :classification=>"true"}
#      uri = last_response.body
#      val = wait_for_task(uri)
#      puts val
#      #get "/"+val.split("/")[-1]


#      d = OpenTox::Dataset.find("https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R545",SUBJECTID)
#      puts d.compounds.inspect
#      exit

#      f = File.new("data/ambit-dataset.rdf")
#      d = ValidationExamples::Util.upload_dataset(f, SUBJECTID)
#      puts d
      
#      d = OpenTox::Dataset.find("https://ambit.uni-plovdiv.bg:8443/ambit2/dataset/R401560",SUBJECTID)
#      #puts d.compounds.to_yaml
#      #puts d.features.keys.to_yaml
#      puts d.to_yaml
#      d2 = d.split(d.compounds[0..5], d.features.keys[0..1], {}, SUBJECTID)
#      puts d2.to_yaml
      
     # run_test("1b")#,:validation_uri=>"http://local-ot/validation/253") #,"http://local-ot/validation/28")#,"http://local-ot/validation/394");
      
      #run_test("3b",:validation_uri=>"http://local-ot/validation/crossvalidation/45") #,{:dataset_uri => "http://local-ot/dataset/773", :prediction_feature => "http://local-ot/dataset/773/feature/Hamster%20Carcinogenicity"})
      
#      p = {
#        :dataset_uri=>"http://local-ot/dataset/527",
#        :algorithm_uri => "http://local-ot/majority/class/algorithm",
#        :prediction_feature=>"http://local-ot/dataset/527/feature/Hamster%20Carcinogenicity",
#        :num_folds => 2 }
      #cv = OpenTox::Crossvalidation.create(p, SUBJECTID)
#      cv = OpenTox::Crossvalidation.find("http://local-ot/validation/crossvalidation/17", SUBJECTID)
#      puts cv.uri
##      puts cv.find_or_create_report.uri
#      puts cv.summary(SUBJECTID).inspect 

      #puts OpenTox::Authorization.list_policy_uris(SUBJECTID).inspect
      
      #puts OpenTox::Authorization.list_policy_uris(SUBJECTID).inspect

      #run_test("19d") #,{:dataset_uri => "http://local-ot/dataset/313", :prediction_feature => "http://local-ot/dataset/313/feature/repdose_classification"})
      
#      model = OpenTox::Model::Generic.find("http://local-ot/majority/class/model/58")
#      OpenTox::QMRFReport.create(model)
      
      
      #get "/12123123123123123"
      #get "/chain"
      
      #OpenTox::RestClientWrapper.get("http://local-ot/validation/task-error")
      #get "/error",nil,'HTTP_ACCEPT' => "application/rdf+xml"
      #puts ""
      #puts ""
      #puts last_response.body 
      #exit
      
#      get "/error"
#      puts last_response.body

      #delete "/1",:subjectid=>SUBJECTID
      
      run_test("19i")
      
      #run_test("3a","http://local-ot/validation/crossvalidation/4")
      #run_test("3b","http://local-ot/validation/crossvalidation/3")
      
      #run_test("8a", "http://local-ot/validation/crossvalidation/6")
      #run_test("8b", "http://local-ot/validation/crossvalidation/5")
  
      #run_test("11b", "http://local-ot/validation/crossvalidation/2" )# //local-ot/validation/42")#, "http://local-ot/validation/report/validation/8") #,"http://local-ot/validation/report/validation/36") #, "http://local-ot/validation/321")
     # run_test("7a","http://local-ot/validation/40") #,"http://local-ot/validation/crossvalidation/10") #, "http://local-ot/validation/321")
      #run_test("8b", "http://local-ot/validation/crossvalidation/4")
   
      #puts Nightly.build_nightly("1")
      
      #prepare_examples
      #do_test_examples # USES CURL, DO NOT FORGET TO RESTART VALIDATION SERVICE
      #do_test_examples_ortona
    
    rescue => ex
      rep = OpenTox::ErrorReport.create(ex, "")
      puts rep.to_yaml
    ensure
      #OpenTox::Authorization.logout(SUBJECTID) if AA_SERVER
    end
  end

  def app
    Sinatra::Application
  end
  
  def run_test(select=nil, overwrite={}, delete=false )
    
    if AA_SERVER && SUBJECTID && delete
      policies_before = OpenTox::Authorization.list_policy_uris(SUBJECTID)
    end
    
    puts ValidationExamples.list unless select
    validationExamples = ValidationExamples.select(select)
    validationExamples.each do |vv|
      vv.each do |v| 
        ex = v.new
        ex.subjectid = SUBJECTID
        
        overwrite.each do |k,v|
          ex.send(k.to_s+"=",v)
        end
        
        unless ex.validation_uri
          ex.upload_files
          ex.check_requirements
          ex.validate
            
          LOGGER.debug "validation done '"+ex.validation_uri.to_s+"'"
        end
        if !delete and ex.validation_uri
          if SUBJECTID
            puts ex.validation_uri+"?subjectid="+CGI.escape(SUBJECTID)
          else
            puts ex.validation_uri
          end
        end
          
        unless ex.report_uri
          ex.report
        end
        if !delete and ex.report_uri
          if SUBJECTID  
            puts ex.report_uri+"?subjectid="+CGI.escape(SUBJECTID)
          else
            puts ex.report_uri
          end
        end
        ##ex.verify_yaml
        ##ex.compare_yaml_vs_rdf
        ex.delete if delete
      end
    end
    
    if AA_SERVER && SUBJECTID && delete
      policies_after= OpenTox::Authorization.list_policy_uris(SUBJECTID)
      diff = policies_after.size - policies_before.size
      if (diff != 0)
        policies_before.each do |k,v|
          policies_after.delete(k)
        end
        LOGGER.warn diff.to_s+" policies NOT deleted:\n"+policies_after.collect{|k,v| k.to_s+" => "+v.to_s}.join("\n")
      else
        LOGGER.debug "all policies deleted"
      end
    end      
  end
  
  def prepare_examples
    get '/prepare_examples'
  end  
  
 def do_test_examples # USES CURL, DO NOT FORGET TO RESTART
   post '/test_examples'
 end
 
  def do_test_examples_ortona 
   post '/test_examples',:examples=>"http://ortona.informatik.uni-freiburg.de/validation/examples"
 end
  
end
