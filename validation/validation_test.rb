ENV['RACK_ENV'] = 'test'
require 'application.rb'
require 'test/unit'
require 'rack/test'
require 'lib/test_util.rb'
LOGGER = Logger.new(STDOUT)
LOGGER.datetime_format = "%Y-%m-%d %H:%M:%S "

WS_DATA=@@config[:services]["opentox-dataset"] #"localhost:4002"
#FILE=File.new("data/hamster_carcinogenicity.owl","r")
FILE=File.new("data/hamster_carcinogenicity.yaml","r")
FILE_TRAIN=File.new("data/hamster_carcinogenicity.owl","r")
FILE_TEST=File.new("data/hamster_carcinogenicity.owl","r")
#FEATURE_URI="http://localhost/toxmodel/feature#Hamster%20Carcinogenicity%20(DSSTOX/CPDB)"
FEATURE_URI="http://localhost/toxmodel/feature#Hamster Carcinogenicity (DSSTOX/CPDB)"
#WS_CLASS_ALG="http://webservices.in-silico.ch/test/algorithm/lazar"
WS_CLASS_ALG=File.join(@@config[:services]["opentox-algorithm"],"lazar") #"localhost:4003/lazar"
WS_FEATURE_ALG=File.join(@@config[:services]["opentox-algorithm"],"fminer") #"localhost:4003/fminer"

class Example
  attr_accessor :alg, :train_data, :test_data, :model, :pred_data, :act_feat, :pred_feat, :classification, :alg_params  
end

class ValidationTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include Lib::TestUtil
  
  def test_it
  
      #prepare_examples
      #do_test_examples # USES CURL, DO NOT FORGET TO RESTART
      validate_prediction_dataset(ex_ntua)
      #validate_model(ex_ntua)
      #validate_algorithm(ex_ntua2)
      
      #test_dataset = OpenTox::Dataset.find ex_ntua2.pred_data
      #puts ex_ntua2.pred_data.to_s+", "+test_dataset.compounds.size.to_s+" compounds"
      #puts test_dataset.compounds.collect{|c| c.to_s}.join("\n")
  end

  def app
    Sinatra::Application
  end
  
  def ex_ntua2
    ex = Example.new
    ex.classification = false
    ex.alg = "http://opentox.ntua.gr:3000/algorithm/mlr"
    ex.train_data = "http://apps.ideaconsult.net:8180/ambit2/dataset/54" #53
    ex.test_data = "http://apps.ideaconsult.net:8180/ambit2/dataset/55" #53
    ex.act_feat = "http://apps.ideaconsult.net:8180/ambit2/feature/22200" #22190"
    # example model
    ex.model = "http://opentox.ntua.gr:3000/model/29"
    ex.pred_feat = "http://ambit.uni-plovdiv.bg:8080/ambit2/feature/261687"
    # example prediction data
    ex.pred_data = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/625"
    return ex
  end
  
  def ex_ntua
    ex = Example.new
    ex.classification = false
    ex.alg = "http://opentox.ntua.gr:3000/algorithm/mlr"
    ex.train_data = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/342"
    ex.test_data = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/342"
    ex.act_feat = "http://ambit.uni-plovdiv.bg:8080/ambit2/feature/103141"
    # example model
    ex.model = "http://opentox.ntua.gr:3000/model/9"
    ex.pred_feat = "http://ambit.uni-plovdiv.bg:8080/ambit2/feature/227289"
    # example prediction data
    ex.pred_data = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/407"
    return ex
  end
  
  def ex_tum
    ex = Example.new
    ex.classification = false
    ex.alg = "http://opentox.informatik.tu-muenchen.de:8080/OpenTox-dev/algorithm/kNNregression"
    ex.train_data = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/342"
    ex.test_data = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/342"
    ex.act_feat = "http://ambit.uni-plovdiv.bg:8080/ambit2/feature/103141"
    # example model
    ex.model = "http://opentox.informatik.tu-muenchen.de:8080/OpenTox-dev/model/TUMOpenToxModel_kNN_11"
    ex.pred_feat = "http://ambit.uni-plovdiv.bg:8080/ambit2/feature/261129"
    # example prediction data
    ex.pred_data = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/601"
    return ex
  end



#  def test_all_validations
#    get '/'
#    assert last_response.ok?
#    puts "all validations:\n"+last_response.body
#    validations = last_response.body.split("\n")
#    puts validations.inspect
#    if validations && validations.size>0
#      validations.each do |v|
#        get v
#        puts "get "+v+":\n"+last_response.body
#        assert last_response.ok? || last_response.status==202
#      end
#    end
#  end
#
#  def test_all_cvs
#    get '/crossvalidations'
#    assert last_response.ok?
#    puts "all crossvalidations:\n"+last_response.body+"\n"
#    crossvalidations = last_response.body.split("\n")
#    #puts crossvalidations.inspect
#    if crossvalidations && crossvalidations.size>0
#      crossvalidations.each do |v|
#        get v
#        puts "get "+v+":\n"+last_response.body
#        assert last_response.ok? || last_response.status==202
#      end
#    end   
#  end
#  
#  def test_cv
#    begin
#      data_uri = upload_data(WS_DATA, FILE)
#      
##      first_validation=nil
##      2.times do 
#        
#        num_folds = 9
#        post '/crossvalidation', { :dataset_uri => data_uri, :algorithm_uri => WS_CLASS_ALG, :prediction_feature => FEATURE_URI,
#           :algorithm_params => "feature_generation_uri="+WS_FEATURE_ALG, :num_folds => num_folds, :random_seed => 2 }
#      
#        uri = last_response.body
#        if OpenTox::Utils.task_uri?(uri)
#          puts "task: "+uri.to_s
#          uri = OpenTox::Task.find(uri).wait_for_resource.to_s
#        end
#        puts "crossvalidation: "+uri
#        
#        assert last_response.ok?
#        crossvalidation_id = uri.split("/")[-1]
#        add_resource("/crossvalidation/"+crossvalidation_id)
#        puts "id:"+crossvalidation_id
#      
#        get '/crossvalidation/'+crossvalidation_id
#        puts last_response.body
#        assert last_response.ok? || last_response.status==202
#        
#        get '/crossvalidation/'+crossvalidation_id+'/validations'
#        puts "validations:\n"+last_response.body
#        assert last_response.ok?
#        assert last_response.body.split("\n").size == num_folds, "num-folds:"+num_folds.to_s+" but num lines is "+last_response.body.split("\n").size.to_s
#        
##        if first_validation
##          # assert that both cross validaitons use the same datasets
##          first_validation2 = last_response.body.split("\n")[0].split("/")[-1]
##          
##          get '/'+first_validation+'/test_dataset_uri'
##          assert last_response.ok?
##          first_val_test_data = last_response.body
##
##          get '/'+first_validation2+'/test_dataset_uri'
##          assert last_response.ok?
##          first_val2_test_data = last_response.body
##          assert first_val_test_data==first_val2_test_data
##        end
##        first_validation = last_response.body.split("\n")[0].split("/")[-1]
##      end
#    ensure
#      #delete_resources
#    end
#  end
#
  def validate_model(ex)
    begin
#      data_uri_train = upload_data(WS_DATA, DATA_TRAIN, FILE_TRAIN)
#      data_uri_test = upload_data(WS_DATA, DATA_TEST, FILE_TEST)
#      #data_uri_train = WS_DATA+"/"+DATA_TRAIN
#      #data_uri_test = WS_DATA+"/"+DATA_TEST
#       
#      if WS_FEATURE_ALG
#        feature_uri = RestClient.post WS_FEATURE_ALG, :dataset_uri => data_uri_train
#        model_uri = RestClient.post(WS_CLASS_ALG,{ :activity_dataset_uri => data_uri_train, :feature_dataset_uri => feature_uri })
#      else
#        model_uri = RestClient.post(WS_CLASS_ALG,{ :dataset_uri => data_uri_train })
#      end 
      
#      model_uri = "http://ot.model.de/1"
#      data_uri_test = "http://ot.dataset.de/3"
      
      #model_uri = "http://ot.model.de/7" 
      #data_uri_test = "http://ot.dataset.de/41"
      
     # model_uri = "http://opentox.ntua.gr:3000/model/9"
     # data_uri_test = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/342"
      
      post '', {:test_dataset_uri => ex.test_data, :model_uri => ex.model} #, :prediction_feature => FEATURE_URI}
      
      puts last_response.body
      #verify_validation
      
      task = OpenTox::Task.find(last_response.body)
      task.wait_for_completion
      val_uri = task.resource
      puts val_uri
      
      get val_uri
      verify_validation(last_response.body)

    ensure
      #delete_resources
    end
  end
  
  def validate_algorithm(ex)
    begin
      
      #get '/41',nil,'HTTP_ACCEPT' => "application/rdf+xml" #"text/x-yaml"
      #puts last_response.body
      
      #data_uri_train = upload_data(WS_DATA, FILE_TRAIN)
      #data_uri_test = upload_data(WS_DATA, FILE_TEST)
      
      #data_uri_train = WS_DATA+"/"+DATA_TRAIN
      #data_uri_test = WS_DATA+"/"+DATA_TEST
      
      
#      data_uri_train="http://ot.dataset.de/57"
#      data_uri_test="http://ot.dataset.de/56"
#      feature_uri = FEATURE_URI
#      algorithm_uri = WS_CLASS_ALG
#      algorithm_params="feature_generation_uri="+WS_FEATURE_ALG
      
      #data_uri_train="http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/342"
      #data_uri_test=data_uri_train
      #feature_uri = "http://ambit.uni-plovdiv.bg:8080/ambit2/feature/103141"
      #algorithm_uri = "http://opentox.ntua.gr:3000/algorithm/mlr"
      #algorithm_params=nil
      
      #post '', { :training_dataset_uri => data_uri_train, :test_dataset_uri => data_uri_test,
        #:algorithm_uri => algorithm_uri, :prediction_feature => feature_uri, :algorithm_params => algorithm_params }
      post '', { :training_dataset_uri => ex.train_data, :test_dataset_uri => ex.test_data,
        :algorithm_uri => ex.alg, :prediction_feature => ex.act_feat, :algorithm_params => ex.alg_params }
        
      task = OpenTox::Task.find(last_response.body)
      task.wait_for_completion
      val_uri = task.resource
      puts val_uri
      get val_uri
      verify_validation(last_response.body)
      #verify_validation
    ensure
      #delete_resources
    end
  end  
  
  def validate_prediction_dataset(ex)
    
#    classification = false
#    test_dataset_uri = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/342"
#    prediction_dataset_uri = "http://ambit.uni-plovdiv.bg:8080/ambit2/dataset/407"
#    actual_feature="http://ambit.uni-plovdiv.bg:8080/ambit2/feature/103141"
#    predicted_feature = OpenTox::Model::PredictionModel.find("http://opentox.ntua.gr:3000/model/9").predicted_variables
#    assert predicted_feature=="http://ambit.uni-plovdiv.bg:8080/ambit2/feature/227289","nope: "+predicted_feature.to_s
#    #predicted_feature="http://ambit.uni-plovdiv.bg:8080/ambit2/feature/227289"

#    classification = false
#    test_dataset_uri = EX2_TEST
#    prediction_dataset_uri = EX2_PRED
#    actual_feature= EX2_ACT_FEAT
#    predicted_feature = OpenTox::Model::PredictionModel.find(EX2_MODEL).predicted_variables
#    assert predicted_feature==EX2_PRED_FEAT,"nope: "+predicted_feature.to_s

#    classification = true
#    test_dataset_uri = "http://ot.dataset.de/1"
#    prediction_dataset_uri = "http://ot.dataset.de/5"
#    actual_feature=URI.encode(FEATURE_URI)
#    predicted_feature = OpenTox::Model::PredictionModel.find("http://ot.model.de/1").predicted_variables#_lazar_classification
#    assert predicted_feature==URI.encode(FEATURE_URI+"_lazar_classification"), predicted_feature
#    #predicted_feature="http://www.epa.gov/NCCT/dsstox/CentralFieldDef.html#ActivityOutcome_CPDBAS_Hamster_lazar_prediction"


    #puts Lib::OTPredictions.new( classification, test_dataset_uri, actual_feature, prediction_dataset_uri, predicted_feature ).compute_stats.each{|key,value| puts key.to_s+" => "+value.to_s }
    
    predicted_feature = OpenTox::Model::PredictionModel.find(ex.model).predicted_variables
    assert predicted_feature==ex.pred_feat,"nope: "+predicted_feature.to_s
    
    puts Lib::OTPredictions.new( ex.classification, ex.test_data, ex.act_feat, ex.pred_data, ex.pred_feat ).compute_stats.each{|key,value| puts key.to_s+" => "+value.to_s }
  end

  
#  def test_split
#    begin
#      
##      model = OpenTox::Model::PredictionModel.find("http://ot.model.de/66")
##      puts model.predicted_variables
##      exit
#      
#      data_uri = upload_data(WS_DATA, FILE)
#      #data_uri =  "http://ot.dataset.de/199" #bbrc
#      #data_uri = "http://ot.dataset.de/67" #hamster
#      #puts data_uri
#
#      #exit
#      
#      #data_uri=WS_DATA+"/"+DATA
#      post '/training_test_split', { :dataset_uri => data_uri, :algorithm_uri => WS_CLASS_ALG, :prediction_feature => FEATURE_URI,
#        :algorithm_params => "feature_generation_uri="+WS_FEATURE_ALG, :split_ratio=>0.75, :random_seed=>6}
#      puts last_response.body
#      
#      task = OpenTox::Task.find(last_response.body)
#      task.wait_for_completion
#      val_uri = task.resource
#      puts val_uri
#            
#      get val_uri
#      puts last_response.body
#      #verify_validation
#    ensure
#      #delete_resources
#    end
#  end
  
  
  def verify_validation(val_yaml)
    
    puts val_yaml
    val = YAML.load(val_yaml)

    puts val.inspect
    assert_integer val["num_instances".to_sym],0,1000
    num_instances = val["num_instances".to_sym].to_i
    
    assert_integer val["num_unpredicted".to_sym],0,num_instances
    num_unpredicted = val["num_unpredicted".to_sym].to_i
    assert_float val["percent_unpredicted".to_sym],0,100
    assert_float_equal(val["percent_unpredicted".to_sym].to_f,100*num_unpredicted/num_instances.to_f,"percent_unpredicted")
    
    assert_integer val["num_without_class".to_sym],0,num_instances
    num_without_class = val["num_without_class".to_sym].to_i
    assert_float val["percent_without_class".to_sym],0,100
    assert_float_equal(val["percent_without_class".to_sym].to_f,100*num_without_class/num_instances.to_f,"percent_without_class")
    
    class_stats = val["classification_statistics".to_sym]
    if class_stats
      class_value_stats = class_stats["class_value_statistics".to_sym]
      class_values = []
      class_value_stats.each do |cvs|
        class_values << cvs["class_value".to_sym]
      end
      puts class_values.inspect
      
      confusion_matrix = class_stats["confusion_matrix".to_sym]
      confusion_matrix_cells = confusion_matrix["confusion_matrix_cell".to_sym]
      predictions = 0
      confusion_matrix_cells.each do |confusion_matrix_cell|
        predictions += confusion_matrix_cell["confusion_matrix_value".to_sym].to_i
      end
      assert_int_equal(predictions, num_instances-num_unpredicted)
    else
      regr_stats = val["regression_statistics".to_sym]
      assert regr_stats!=nil
    end
  end
  
  def assert_int_equal(val1,val2,msg_suffix=nil)
    assert(val1==val2,msg_suffix.to_s+" not equal: "+val1.to_s+" != "+val2.to_s)
  end
  
  def assert_float_equal(val1,val2,msg_suffix=nil,epsilon=0.0001)
    assert((val1-val2).abs<epsilon,msg_suffix.to_s+" not equal: "+val1.to_s+" != "+val2.to_s+", diff:"+(val1-val2).abs.to_s)
  end
  
  def assert_integer(string_val, min=nil, max=nil)
    assert string_val.to_i.to_s==string_val.to_s, string_val.to_s+" not an integer"
    assert string_val.to_i>=min if min!=nil
    assert string_val.to_i<=max if max!=nil
  end
  
  def assert_float(string_val, min=nil, max=nil)
    assert( string_val.to_f.to_s==string_val.to_s || (string_val.to_f.to_s==(string_val.to_s+".0")),
      string_val.to_s+" not a float (!="+string_val.to_f.to_s+")")
    assert string_val.to_f>=min if min!=nil
    assert string_val.to_f<=max if max!=nil
  end
  
#  def test_nothing
#    
#    #puts "testing nothing"
#    
#    #get '/'     
#
#    #get '/crossvalidation/loo'
#    #get '/training_test_split'
#
#    #get '/1',nil,'HTTP_ACCEPT' => "application/rdf+xml"
#    #get '/1',nil,'HTTP_ACCEPT' => "text/x-yaml"
#
#    
#    #get '/crossvalidation/1',nil,'HTTP_ACCEPT' => "application/rdf+xml"
#    #get '/crossvalidation/1/statistics',nil,'HTTP_ACCEPT' => "text/x-yaml"
#    
#    #puts last_response.body
#    
#    #get '/2'
#    #verify_validation(last_response.body)
#    
#  end
  
#  private
#  def verify_validation (delete=true)
#    
#    puts "validation: "+last_response.body
#    assert last_response.ok?
#    validation_id = last_response.body.split("/")[-1]
#
#    puts "uri: "+last_response.body
#    puts "id:"+validation_id
#    add_resource("/"+validation_id) if delete
#
#    #get '/'+validation_id,nil,'HTTP_ACCEPT' => "application/rdf+xml"
#    get '/'+validation_id,nil,'HTTP_ACCEPT' => "text/x-yaml"
#    puts last_response.body
#    assert last_response.ok? || last_response.status==202
#
##    ["test_dataset_uri", "model_uri", "prediction_dataset_uri"].each do |t|
##      get '/'+validation_id+'/'+t
##      puts ""+t+": "+last_response.body
##      assert last_response.ok?
##      
##      content = ext("curl "+last_response.body)
##      content = content.split("\n")[0,10].join("\n")+"\n...\n" if content.count("\n")>10
##      puts content
##    end
#  end

  def prepare_examples
    get '/prepare_examples'
  end  
  
 def do_test_examples # USES CURL, DO NOT FORGET TO RESTART
   get '/test_examples'
 end
end
