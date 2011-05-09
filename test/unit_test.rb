#TEST_USER = "mgtest"
#TEST_PW = "mgpasswd"
ENV['RACK_ENV'] = 'production'

require "rubygems"
require "sinatra"
require "uri"
require "yaml"
require 'application.rb'
require 'test/unit'
require 'rack/test'
require 'lib/test_util.rb'
require 'test/test_examples.rb'

TEST_USER = "guest"
TEST_PW = "guest"

#LOGGER = OTLogger.new(STDOUT)
#LOGGER.datetime_format = "%Y-%m-%d %H:%M:%S "
#LOGGER.formatter = Logger::Formatter.new

module Sinatra
  set :raise_errors, false
  set :show_exceptions, false
end

class Exception
  def message
    errorCause ? errorCause.to_yaml : to_s
  end
end

class ValidationTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include Lib::TestUtil
  
  def global_setup
    puts "login and upload datasets"
    if AA_SERVER
      @@subjectid = OpenTox::Authorization.authenticate(TEST_USER,TEST_PW)
      raise "could not log in" unless @@subjectid
      puts "logged in: "+@@subjectid.to_s
    else
      puts "AA disabled"
      @@subjectid = nil
    end

    @@data = []
    files = { File.new("data/hamster_carcinogenicity.mini.csv") => :crossvalidation,  
              File.new("data/EPAFHM.mini.csv") => :crossvalidation,
              File.new("data/hamster_carcinogenicity.csv") => :validation,
              File.new("data/EPAFHM.csv") => :validation,
#              File.new("data/StJudes-HepG2-testset_Class.csv") => :crossvalidation
               }
    files.each do |file,type|
      @@data << { :type => type,
        :data => ValidationExamples::Util.upload_dataset(file, @@subjectid),
        :feat => ValidationExamples::Util.prediction_feature_for_file(file),
        :info => file.path, :delete => true} 
    end
#    @@data << { :type => :crossvalidation,
#      :data => "http://apps.ideaconsult.net:8080/ambit2/dataset/9?max=50",
#      :feat => "http://apps.ideaconsult.net:8080/ambit2/feature/21573",
#      :info => "http://apps.ideaconsult.net:8080/ambit2/dataset/9?max=50" }
#    @@data << { :type => :validation,
#      :data => "http://apps.ideaconsult.net:8080/ambit2/dataset/272?max=50",
#      :feat => "http://apps.ideaconsult.net:8080/ambit2/feature/26221",
#      :info => "http://apps.ideaconsult.net:8080/ambit2/dataset/272?max=50" } 
  end
  
  def global_teardown
    puts "delete and logout"
    @@data.each{|data| OpenTox::Dataset.find(data[:data],@@subjectid).delete(@@subjectid) if data[:delete]}
    @@vs.each{|v| v.delete(@@subjectid)} if defined?@@vs
    @@cvs.each{|cv| cv.delete(@@subjectid)} if defined?@@cvs
    @@reports.each{|report| report.delete(@@subjectid)} if defined?@@reports
    @@qmrfReports.each{|qmrfReport| qmrfReport.delete(@@subjectid)} if defined?@@qmrfReports
    OpenTox::Authorization.logout(@@subjectid) if AA_SERVER
  end
  
  def test_validation_list
    puts "test_validation_list"
    list = OpenTox::Validation.list
    assert list.is_a?(Array)
    list.each do |l|
      assert l.uri?
    end
  end
 
  def test_training_test_split
    
    @@vs = []
    @@data.each do |data|
      if data[:type]==:validation
        puts "test_training_test_split "+data[:info].to_s
        p = { 
          :dataset_uri => data[:data],
          :algorithm_uri => File.join(CONFIG[:services]["opentox-algorithm"],"lazar"),
          :algorithm_params => "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc"),
          :prediction_feature => data[:feat],
          :split_ratio => 0.95,
          :random_seed => 2}
        t = OpenTox::SubTask.new(nil,0,1)
        def t.progress(pct)
          if !defined?@last_msg or @last_msg+3<Time.new
            puts "waiting for training-test-split validation: "+pct.to_s
            @last_msg=Time.new
          end
        end
        def t.waiting_for(task_uri); end
        v = OpenTox::Validation.create_training_test_split(p, @@subjectid, t)
        assert v.uri.uri?
        if @@subjectid
          assert_rest_call_error OpenTox::NotAuthorizedError do
            OpenTox::Crossvalidation.find(v.uri)
          end
        end
        v = OpenTox::Validation.find(v.uri, @@subjectid)
        assert v.uri.uri?
        
        model = v.metadata[OT.model]
        assert model.uri?
        v_list = OpenTox::Validation.list( {:model => model} )
        assert v_list.size==1 and v_list.include?(v.uri)
        @@vs << v
      end
    end
  end
  
  def test_validation_report
    #@@cv = OpenTox::Crossvalidation.find("http://local-ot/validation/crossvalidation/48", @@subjectid)
    
    @@reports = [] unless defined?@@reports
    @@vs.each do |v|
      puts "test_validation_report"
      assert defined?v,"no validation defined"
      assert_kind_of OpenTox::Validation,v
      if @@subjectid
        assert_rest_call_error OpenTox::NotAuthorizedError do
          OpenTox::CrossvalidationReport.create(v.uri)
        end
      end
      report = OpenTox::ValidationReport.find_for_validation(v.uri,@@subjectid)
      assert report==nil,"report already exists for validation\nreport: "+(report ? report.uri.to_s : "")+"\nvalidation: "+v.uri.to_s
      report = OpenTox::ValidationReport.create(v.uri,@@subjectid)
      assert report.uri.uri?
      if @@subjectid
        assert_rest_call_error OpenTox::NotAuthorizedError do
          OpenTox::CrossvalidationReport.find(report.uri)
        end
      end
      report = OpenTox::ValidationReport.find(report.uri,@@subjectid)
      assert report.uri.uri?
      report2 = OpenTox::ValidationReport.find_for_validation(v.uri,@@subjectid)
      assert_equal report.uri,report2.uri
      report3_uri = v.find_or_create_report(@@subjectid)
      assert_equal report.uri,report3_uri
      @@reports << report2
    end  
  end

  def test_crossvalidation_list
    puts "test_crossvalidation_list"
    list = OpenTox::Crossvalidation.list
    assert list.is_a?(Array)
    list.each do |l|
      assert l.uri?
    end
  end

  def test_crossvalidation
    
    #assert_rest_call_error OpenTox::NotFoundError do 
    #  OpenTox::Crossvalidation.find(File.join(CONFIG[:services]["opentox-validation"],"crossvalidation/noexistingid"))
    #end
    @@cvs = []
    @@data.each do |data|
      if data[:type]==:crossvalidation
        puts "test_crossvalidation "+data[:info].to_s
        p = { 
          :dataset_uri => data[:data],
          :algorithm_uri => File.join(CONFIG[:services]["opentox-algorithm"],"lazar"),
          :algorithm_params => "feature_generation_uri="+File.join(CONFIG[:services]["opentox-algorithm"],"fminer/bbrc"),
          :prediction_feature => data[:feat],
          :num_folds => 2 }
        t = OpenTox::SubTask.new(nil,0,1)
        def t.progress(pct)
          if !defined?@last_msg or @last_msg+3<Time.new
            puts "waiting for crossvalidation: "+pct.to_s
            @last_msg=Time.new
          end
        end
        def t.waiting_for(task_uri); end
        cv = OpenTox::Crossvalidation.create(p, @@subjectid, t)
        assert cv.uri.uri?
        if @@subjectid
          assert_rest_call_error OpenTox::NotAuthorizedError do
            OpenTox::Crossvalidation.find(cv.uri)
          end
        end
        cv = OpenTox::Crossvalidation.find(cv.uri, @@subjectid)
        assert cv.uri.uri?
        if @@subjectid
          assert_rest_call_error OpenTox::NotAuthorizedError do
            cv.summary(cv)
          end
        end
        summary = cv.summary(@@subjectid)
        assert_kind_of Hash,summary
        
        algorithm = cv.metadata[OT.algorithm]
        assert algorithm.uri?
        cv_list = OpenTox::Crossvalidation.list( {:algorithm => algorithm} )
        assert cv_list.include?(cv.uri)
        cv_list.each do |cv_uri|
          alg = OpenTox::Crossvalidation.find(cv_uri).metadata[OT.algorithm]
          assert alg==algorithm,"wrong algorithm for filtered crossvalidation, should be: '"+algorithm.to_s+"', is: '"+alg.to_s+"'"
        end
        
        @@cvs << cv
      end
    end
  end
    
  def test_crossvalidation_report
    #@@cv = OpenTox::Crossvalidation.find("http://local-ot/validation/crossvalidation/48", @@subjectid)
    
    @@reports = [] unless defined?@@reports
    @@cvs.each do |cv|
      puts "test_crossvalidation_report"
      assert defined?cv,"no crossvalidation defined"
      assert_kind_of OpenTox::Crossvalidation,cv
      #assert_rest_call_error OpenTox::NotFoundError do 
      #  OpenTox::CrossvalidationReport.find_for_crossvalidation(cv.uri)
      #end
      if @@subjectid
        assert_rest_call_error OpenTox::NotAuthorizedError do
          OpenTox::CrossvalidationReport.create(cv.uri)
        end
      end
      assert OpenTox::ValidationReport.find_for_validation(cv.uri,@@subjectid)==nil
      report = OpenTox::CrossvalidationReport.create(cv.uri,@@subjectid)
      assert report.uri.uri?
      if @@subjectid
        assert_rest_call_error OpenTox::NotAuthorizedError do
          OpenTox::CrossvalidationReport.find(report.uri)
        end
      end
      report = OpenTox::CrossvalidationReport.find(report.uri,@@subjectid)
      assert report.uri.uri?
      report2 = OpenTox::CrossvalidationReport.find_for_crossvalidation(cv.uri,@@subjectid)
      assert_equal report.uri,report2.uri
      report3_uri = cv.find_or_create_report(@@subjectid)
      assert_equal report.uri,report3_uri
      @@reports << report2
    end  
  end
  
  def test_qmrf_report
    #@@cv = OpenTox::Crossvalidation.find("http://local-ot/validation/crossvalidation/13", @@subjectid)
    
    @@qmrfReports = []
    @@cvs.each do |cv|
      puts "test_qmrf_report"
      assert defined?cv,"no crossvalidation defined"
      validations = cv.metadata[OT.validation]
      assert_kind_of Array,validations
      assert validations.size==cv.metadata[OT.numFolds].to_i,validations.size.to_s+"!="+cv.metadata[OT.numFolds].to_s
      val = OpenTox::Validation.find(validations[0], @@subjectid)
      model_uri = val.metadata[OT.model]
      
      model = OpenTox::Model::Generic.find(model_uri, @@subjectid)
      assert model!=nil
      
      #assert_rest_call_error OpenTox::NotFoundError do 
      #  OpenTox::QMRFReport.find_for_model(model_uri, @@subjectid)
      #end
      
      @@qmrfReports << OpenTox::QMRFReport.create(model_uri, @@subjectid)
    end
  end
  
  ################### utils and overrides ##########################
  
  def app
    Sinatra::Application
  end
  
  # checks RestCallError type
  def assert_rest_call_error( ex )
    if ex==OpenTox::NotAuthorizedError and @@subjectid==nil
      puts "AA disabled: skipping test for not authorized"
      return
    end
    begin
      yield
    rescue OpenTox::RestCallError => e
      report = e.errorCause
      while report.errorCause
        report = report.errorCause
      end
      assert_equal report.errorType,ex.to_s
    end
  end
  
  # hack to have a global_setup and global_teardown 
  def teardown
    if((@@expected_test_count-=1) == 0)
      global_teardown
    end
  end
  def setup
    unless defined?@@expected_test_count
      @@expected_test_count = (self.class.instance_methods.reject{|method| method[0..3] != 'test'}).length
      global_setup
    end
  end

end

  
