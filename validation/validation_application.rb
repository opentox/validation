
[ 'rubygems', 'sinatra', 'sinatra/url_for', 'opentox-ruby' ].each do |lib|
  require lib
end

require 'lib/dataset_cache.rb'
require 'validation/validation_service.rb'

get '/crossvalidation/?' do
  LOGGER.info "list all crossvalidations"
  model_uri = params.delete("model") || params.delete("model_uri")
  if model_uri
    model = OpenTox::Model::Generic.find(model_uri, @subjectid)
    params[:algorithm] = model.metadata[OT.algorithm]
    params[:dataset] = model.metadata[OT.trainingDataset]
  end
  uri_list = Lib::OhmUtil.find( Validation::Crossvalidation, params ).sort.collect{|v| v.crossvalidation_uri}.join("\n") + "\n"
  if request.env['HTTP_ACCEPT'] =~ /text\/html/
    related_links = 
      "Single validations:             "+url_for("/",:full)+"\n"+
      "Leave-one-out crossvalidations: "+url_for("/crossvalidation/loo",:full)+"\n"+
      "Crossvalidation reports:        "+url_for("/report/crossvalidation",:full)
    description = 
      "A list of all crossvalidations.\n"+
      "Use the POST method to perform a crossvalidation."
    post_command = OpenTox::PostCommand.new request.url,"Perform crossvalidation"
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
    post_command.attributes << OpenTox::PostAttribute.new("dataset_uri")
    post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
    post_command.attributes << OpenTox::PostAttribute.new("num_folds",false,"10")
    post_command.attributes << OpenTox::PostAttribute.new("random_seed",false,"1","An equal random seed value ensures the excact same random dataset split.")
    post_command.attributes << OpenTox::PostAttribute.new("stratified",false,"false","Stratification ensures an equal class-value spread in folds.")
    content_type "text/html"
    OpenTox.text_to_html uri_list,@subjectid,related_links,description,post_command
  else
    content_type "text/uri-list"
    uri_list
  end
end

post '/crossvalidation/?' do
  LOGGER.info "creating crossvalidation "+params.inspect
  raise OpenTox::BadRequestError.new "dataset_uri missing" unless params[:dataset_uri].to_s.size>0
  raise OpenTox::BadRequestError.new "algorithm_uri missing" unless params[:algorithm_uri].to_s.size>0
  raise OpenTox::BadRequestError.new "prediction_feature missing" unless params[:prediction_feature].to_s.size>0
  raise OpenTox::BadRequestError.new "illegal param-value num_folds: '"+params[:num_folds].to_s+"', must be integer >1" unless params[:num_folds]==nil or 
    params[:num_folds].to_i>1
    
  task = OpenTox::Task.create( "Perform crossvalidation", url_for("/crossvalidation", :full) ) do |task| #, params
    cv_params = { :dataset_uri => params[:dataset_uri],  
                  :algorithm_uri => params[:algorithm_uri],
                  :loo => "false",
                  :subjectid => params[:subjectid] }
    [ :num_folds, :random_seed ].each{ |sym| cv_params[sym] = params[sym] if params[sym] }
    cv_params[:stratified] = (params[:stratified].size>0 && params[:stratified]!="false" && params[:stratified]!="0") if params[:stratified]
    cv = Validation::Crossvalidation.create cv_params
    cv.subjectid = @subjectid
    cv.perform_cv( params[:prediction_feature], params[:algorithm_params], OpenTox::SubTask.create(task,0,95))
    # computation of stats is cheap as dataset are already loaded into the memory
    Validation::Validation.from_cv_statistics( cv.id, @subjectid, OpenTox::SubTask.create(task,95,100) )
    cv.crossvalidation_uri
  end
  return_task(task)
end

post '/crossvalidation/cleanup/?' do
  LOGGER.info "crossvalidation cleanup, starting..."
  content_type "text/uri-list"
  deleted = []
  Validation::Crossvalidation.all.collect.delete_if{|cv| cv.finished}.each do |cv|
    if OpenTox::Authorization.authorized?(cv.crossvalidation_uri,"DELETE",@subjectid)
      LOGGER.debug "delete cv with id:"+cv.id.to_s+", finished is false"
      deleted << cv.crossvalidation_uri
      cv.subjectid = @subjectid
      cv.delete_crossvalidation
      sleep 1 if AA_SERVER
    end
  end
  LOGGER.info "crossvalidation cleanup, deleted "+deleted.size.to_s+" cvs"
  deleted.join("\n")+"\n"
end

post '/crossvalidation/loo/?' do
  LOGGER.info "creating loo-crossvalidation "+params.inspect
  raise OpenTox::BadRequestError.new "dataset_uri missing" unless params[:dataset_uri].to_s.size>0
  raise OpenTox::BadRequestError.new "algorithm_uri missing" unless params[:algorithm_uri].to_s.size>0
  raise OpenTox::BadRequestError.new "prediction_feature missing" unless params[:prediction_feature].to_s.size>0
  raise OpenTox::BadRequestError.new "illegal param: num_folds, stratified, random_seed not allowed for loo-crossvalidation" if params[:num_folds] or 
    params[:stratifed] or params[:random_seed]
  task = OpenTox::Task.create( "Perform loo-crossvalidation", url_for("/crossvalidation/loo", :full) ) do |task| #, params
    cv_params = { :dataset_uri => params[:dataset_uri],  
                  :algorithm_uri => params[:algorithm_uri],
                  :loo => "true" }
    cv = Validation::Crossvalidation.create cv_params
    cv.subjectid = @subjectid
    cv.perform_cv( params[:prediction_feature], params[:algorithm_params], OpenTox::SubTask.create(task,0,95))
    # computation of stats is cheap as dataset are already loaded into the memory
    Validation::Validation.from_cv_statistics( cv.id, @subjectid, OpenTox::SubTask.create(task,95,100) )
    cv.clean_loo_files( !(params[:algorithm_params] && params[:algorithm_params] =~ /feature_dataset_uri/) )
    cv.crossvalidation_uri
  end
  return_task(task)
end

get '/crossvalidation/loo/?' do
  LOGGER.info "list all crossvalidations"
  params[:loo]="true"
  uri_list = Lib::OhmUtil.find( Validation::Crossvalidation, params ).sort.collect{|v| v.crossvalidation_uri}.join("\n") + "\n"
  if request.env['HTTP_ACCEPT'] =~ /text\/html/
    related_links = 
      "Single validations:      "+url_for("/",:full)+"\n"+
      "All crossvalidations:    "+url_for("/crossvalidation",:full)+"\n"+
      "Crossvalidation reports: "+url_for("/report/crossvalidation",:full)
    description = 
      "A list of all leave one out crossvalidations.\n"+
      "Use the POST method to perform a crossvalidation."
    post_command = OpenTox::PostCommand.new request.url,"Perform leave-one-out-crossvalidation"
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
    post_command.attributes << OpenTox::PostAttribute.new("dataset_uri")
    post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
    content_type "text/html"
    OpenTox.text_to_html uri_list,@subjectid,related_links,description,post_command
  else
    content_type "text/uri-list"
    uri_list
  end
  
end

get '/crossvalidation/:id' do
  LOGGER.info "get crossvalidation with id "+params[:id].to_s
#  begin
#    #crossvalidation = Validation::Crossvalidation.find(params[:id])
#  rescue ActiveRecord::RecordNotFound => ex
#    raise OpenTox::NotFoundError.new "Crossvalidation '#{params[:id]}' not found."
#  end
  crossvalidation = Validation::Crossvalidation.get(params[:id])
  raise OpenTox::NotFoundError.new "Crossvalidation '#{params[:id]}' not found." unless crossvalidation
  
  case request.env['HTTP_ACCEPT'].to_s
  when "application/rdf+xml"
    content_type "application/rdf+xml"
    crossvalidation.to_rdf
  when /text\/html/
    related_links = 
      "Search for corresponding cv report:  "+url_for("/report/crossvalidation?crossvalidation="+crossvalidation.crossvalidation_uri,:full)+"\n"+
      "Statistics for this crossvalidation: "+url_for("/crossvalidation/"+params[:id]+"/statistics",:full)+"\n"+
      "Predictions of this crossvalidation: "+url_for("/crossvalidation/"+params[:id]+"/predictions",:full)+"\n"+
      "All crossvalidations:                "+url_for("/crossvalidation",:full)+"\n"+
      "All crossvalidation reports:         "+url_for("/report/crossvalidation",:full)
    description = 
        "A crossvalidation resource."
    content_type "text/html"
    OpenTox.text_to_html crossvalidation.to_rdf_yaml,@subjectid,related_links,description
  when "application/serialize"
    content_type "application/serialize"
    crossvalidation.inspect # to load all the stuff
    crossvalidation.to_yaml
  when /application\/x-yaml|\*\/\*/
    content_type "application/x-yaml"
    crossvalidation.to_rdf_yaml
  else
    raise OpenTox::BadRequestError.new "MIME type '"+request.env['HTTP_ACCEPT'].to_s+"' not supported, valid Accept-Headers: \"application/rdf+xml\", \"application/x-yaml\", \"text/html\"."
  end
end

get '/crossvalidation/:id/statistics' do
  
  LOGGER.info "get crossvalidation statistics for crossvalidation with id "+params[:id].to_s
  v = Validation::Validation.from_cv_statistics( params[:id], @subjectid )
  case request.env['HTTP_ACCEPT'].to_s
  when /text\/html/
    related_links = 
       "The corresponding crossvalidation resource: "+url_for("/crossvalidation/"+params[:id],:full)
    description = 
       "The averaged statistics for the crossvalidation."
    content_type "text/html"
    OpenTox.text_to_html v.to_rdf_yaml,@subjectid,related_links,description
  when "application/rdf+xml"
    content_type "application/rdf+xml"
    v.to_rdf
  when "application/serialize"
    content_type "application/serialize"
    v.inspect # to load all the stuff
    v.to_yaml    
  else
    content_type "application/x-yaml"
    v.to_rdf_yaml
  end
end

get '/crossvalidation/:id/statistics/probabilities' do
  
  LOGGER.info "get crossvalidation statistics for crossvalidation with id "+params[:id].to_s
  raise OpenTox::BadRequestError.new("Missing params, plz give confidence and prediction") unless params[:confidence] and params[:prediction]
  v = Validation::Validation.from_cv_statistics( params[:id], @subjectid )
  props = v.probabilities(params[:confidence].to_s.to_f,params[:prediction].to_s)
  content_type "text/x-yaml"
  props.to_yaml
end

delete '/crossvalidation/:id/?' do
  LOGGER.info "delete crossvalidation with id "+params[:id].to_s
  content_type "text/plain"
#  begin
    #crossvalidation = Validation::Crossvalidation.find(params[:id])
#  rescue ActiveRecord::RecordNotFound => ex
#    raise OpenTox::NotFoundError.new "Crossvalidation '#{params[:id]}' not found."
#  end
#  Validation::Crossvalidation.delete(params[:id])
  
  cv = Validation::Crossvalidation.get(params[:id])
  raise OpenTox::NotFoundError.new "Crossvalidation '#{params[:id]}' not found." unless cv
  cv.subjectid = @subjectid
  cv.delete_crossvalidation
end

#get '/crossvalidation/:id/validations' do
#  LOGGER.info "get all validations for crossvalidation with id "+params[:id].to_s
#  begin
#    crossvalidation = Validation::Crossvalidation.find(params[:id])
#  rescue ActiveRecord::RecordNotFound => ex
#    raise OpenTox::NotFoundError.new "Crossvalidation '#{params[:id]}' not found."
#  end
#  content_type "text/uri-list"
#  Validation::Validation.find( :all, :conditions => { :crossvalidation_id => params[:id] } ).collect{ |v| v.validation_uri.to_s }.join("\n")+"\n"
#end

#get '/crossvalidation/:id/predictions' do
#  LOGGER.info "get predictions for crossvalidation with id "+params[:id].to_s
#  begin
#    #crossvalidation = Validation::Crossvalidation.find(params[:id])
#    crossvalidation = Validation::Crossvalidation.get(params[:id])
#  rescue ActiveRecord::RecordNotFound => ex
#    raise OpenTox::NotFoundError.new "Crossvalidation '#{params[:id]}' not found."
#  end
#  raise OpenTox::BadRequestError.new "Crossvalidation '"+params[:id].to_s+"' not finished" unless crossvalidation.finished
#  
#  content_type "application/x-yaml"
#  validations = Validation::Validation.find( :crossvalidation_id => params[:id], :validation_type => "crossvalidation" )
#  p = Lib::OTPredictions.to_array( validations.collect{ |v| v.compute_validation_stats_with_model(nil, true) } ).to_yaml
#  
#  case request.env['HTTP_ACCEPT'].to_s
#  when /text\/html/
#    content_type "text/html"
#    description = 
#      "The crossvalidation predictions as (yaml-)array."
#    related_links = 
#      "All crossvalidations:         "+url_for("/crossvalidation",:full)+"\n"+
#      "Correspoding crossvalidation: "+url_for("/crossvalidation/"+params[:id],:full)
#    OpenTox.text_to_html p,@subjectid, related_links, description
#  else
#    content_type "text/x-yaml"
#    p
#  end
#end

get '/?' do
  
  LOGGER.info "list all validations, params: "+params.inspect
  uri_list = Lib::OhmUtil.find( Validation::Validation, params ).sort.collect{|v| v.validation_uri}.join("\n") + "\n"
  if request.env['HTTP_ACCEPT'] =~ /text\/html/
    related_links = 
      "To perform a validation:\n"+
      "* "+url_for("/test_set_validation",:full)+"\n"+
      "* "+url_for("/training_test_validation",:full)+"\n"+
      "* "+url_for("/bootstrapping",:full)+"\n"+
      "* "+url_for("/training_test_split",:full)+"\n"+
      "* "+url_for("/crossvalidation",:full)+"\n"+
      "Validation reporting:            "+url_for("/report",:full)+"\n"+
      "REACH relevant reporting:        "+url_for("/reach_report",:full)+"\n"+
      "Examples for using this service: "+url_for("/examples",:full)+"\n"
    description = 
        "A validation web service for the OpenTox project ( http://opentox.org ).\n"+
        "In the root directory (this is where you are now), a list of all validation resources is returned."
    content_type "text/html"
    OpenTox.text_to_html uri_list,@subjectid,related_links,description
  else
    content_type "text/uri-list"
    uri_list
  end
end

post '/?' do
  raise OpenTox::BadRequestError.new "Post not supported, to perfom a validation use '/test_set_validation', '/training_test_validation', 'bootstrapping', 'training_test_split'"
end

post '/test_set_validation' do
  LOGGER.info "creating test-set-validation "+params.inspect
  if params[:model_uri].to_s.size>0 and params[:test_dataset_uri].to_s.size>0 and 
    params[:training_dataset_uri].to_s.size==0 and params[:algorithm_uri].to_s.size==0
    task = OpenTox::Task.create( "Perform test-set-validation", url_for("/", :full) ) do |task| #, params
      v = Validation::Validation.create :validation_type => "test_set_validation", 
                       :model_uri => params[:model_uri], 
                       :test_dataset_uri => params[:test_dataset_uri],
                       :test_target_dataset_uri => params[:test_target_dataset_uri],
                       :prediction_feature => params[:prediction_feature]
      v.subjectid = @subjectid
      v.validate_model( task )
      v.validation_uri
    end
    return_task(task)
  else
    raise OpenTox::BadRequestError.new "illegal parameters, pls specify model_uri and test_dataset_uri\n"+
      "params given: "+params.inspect
  end
end

get '/test_set_validation' do
  LOGGER.info "list all test-set-validations, params: "+params.inspect
  
  #uri_list = Validation::Validation.find( :all, :conditions => { :validation_type => "test_set_validation" } ).collect{ |v| v.validation_uri }.join("\n")+"\n"
  #uri_list = Validation::Validation.all( :validation_type => "test_set_validation" ).collect{ |v| v.validation_uri }.join("\n")+"\n"
  #params[:validation_type] = "test_set_validation"
  #uri_list = Lib::DataMapperUtil.all(Validation::Validation,params).collect{ |v| v.validation_uri }.join("\n")+"\n"
  uri_list = Validation::Validation.find(:validation_type => "test_set_validation").sort.collect{|v| v.validation_uri}.join("\n") + "\n"
  
  if request.env['HTTP_ACCEPT'] =~ /text\/html/
    related_links = 
      "All validations:    "+url_for("/",:full)+"\n"+
      "Validation reports: "+url_for("/report/validation",:full)
    description = 
        "A list of all test-set-validations.\n"+
        "To perform a test-set-validation use the POST method."
    post_command = OpenTox::PostCommand.new request.url,"Perform test-set-validation"
    post_command.attributes << OpenTox::PostAttribute.new("model_uri")
    post_command.attributes << OpenTox::PostAttribute.new("test_dataset_uri")
    post_command.attributes << OpenTox::PostAttribute.new("test_target_dataset_uri",false,nil,"Specify if target endpoint values are not available in test dataset.")
    post_command.attributes << OpenTox::PostAttribute.new("prediction_feature",false,nil,"Default is 'dependentVariables' of the model.")
    content_type "text/html"
    OpenTox.text_to_html uri_list,@subjectid,related_links,description,post_command
  else
    content_type "text/uri-list"
    uri_list
  end
end

post '/training_test_validation/?' do
  LOGGER.info "creating training-test-validation "+params.inspect
  if params[:algorithm_uri].to_s.size>0 and params[:training_dataset_uri].to_s.size>0 and 
    params[:test_dataset_uri].to_s.size>0 and params[:prediction_feature].to_s.size>0 and params[:model_uri].to_s.size==0
    task = OpenTox::Task.create( "Perform training-test-validation", url_for("/", :full) ) do |task| #, params
      v = Validation::Validation.create :validation_type => "training_test_validation", 
                        :algorithm_uri => params[:algorithm_uri],
                        :training_dataset_uri => params[:training_dataset_uri], 
                        :test_dataset_uri => params[:test_dataset_uri],
                        :test_target_dataset_uri => params[:test_target_dataset_uri],
                        :prediction_feature => params[:prediction_feature]
      v.subjectid = @subjectid
      v.validate_algorithm( params[:algorithm_params], task ) 
      v.validation_uri
    end
    return_task(task)
  else
    raise OpenTox::BadRequestError.new "illegal parameters, pls specify algorithm_uri, training_dataset_uri, test_dataset_uri, prediction_feature\n"+
        "params given: "+params.inspect
  end
end

get '/training_test_validation' do
  LOGGER.info "list all training-test-validations, params: "+params.inspect
  #uri_list = Validation::Validation.find( :all, :conditions => { :validation_type => "training_test_validation" } ).collect{ |v| v.validation_uri }.join("\n")+"\n"
  #uri_list = Validation::Validation.all( :validation_type => "training_test_validation" ).collect{ |v| v.validation_uri }.join("\n")+"\n"
  #params[:validation_type] = "training_test_validation"
  #uri_list = Lib::DataMapperUtil.all(Validation::Validation,params).collect{ |v| v.validation_uri }.join("\n")+"\n"
  uri_list = Validation::Validation.find(:validation_type => "training_test_validation").sort.collect{|v| v.validation_uri}.join("\n") + "\n"
  
  if request.env['HTTP_ACCEPT'] =~ /text\/html/
    related_links = 
      "All validations:    "+url_for("/",:full)+"\n"+
      "Validation reports: "+url_for("/report/validation",:full)
    description = 
        "A list of all training-test-validations.\n"+
        "To perform a training-test-validation use the POST method."
    post_command = OpenTox::PostCommand.new request.url,"Perform training-test-validation"
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
    post_command.attributes << OpenTox::PostAttribute.new("training_dataset_uri")
    post_command.attributes << OpenTox::PostAttribute.new("test_dataset_uri")
    post_command.attributes << OpenTox::PostAttribute.new("test_target_dataset_uri",false,nil,"Specify if target endpoint values are not available in test dataset.")
    post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
    content_type "text/html"
    OpenTox.text_to_html uri_list,@subjectid,related_links,description,post_command
  else
    content_type "text/uri-list"
    uri_list
  end
end

post '/bootstrapping' do
  LOGGER.info "performing bootstrapping validation "+params.inspect
  raise OpenTox::BadRequestError.new "dataset_uri missing" unless params[:dataset_uri].to_s.size>0
  raise OpenTox::BadRequestError.new "algorithm_uri missing" unless params[:algorithm_uri].to_s.size>0
  raise OpenTox::BadRequestError.new "prediction_feature missing" unless params[:prediction_feature].to_s.size>0
  task = OpenTox::Task.create( "Perform bootstrapping validation", url_for("/bootstrapping", :full) ) do |task| #, params
    params.merge!( Validation::Util.bootstrapping( params[:dataset_uri], 
      params[:prediction_feature], @subjectid, 
      params[:random_seed], OpenTox::SubTask.create(task,0,33)) )
    LOGGER.info "params after bootstrapping: "+params.inspect
    v = Validation::Validation.create :validation_type => "bootstrapping", 
                     :test_target_dataset_uri => params[:dataset_uri],
                     :prediction_feature => params[:prediction_feature],
                     :algorithm_uri => params[:algorithm_uri],
                     :training_dataset_uri => params[:training_dataset_uri], 
                     :test_dataset_uri => params[:test_dataset_uri]
    v.subjectid = @subjectid
    v.validate_algorithm( params[:algorithm_params], OpenTox::SubTask.create(task,33,100))
    v.validation_uri
  end
  return_task(task)
end

get '/bootstrapping' do
  LOGGER.info "list all bootstrapping-validations, params: "+params.inspect
  #uri_list = Validation::Validation.find( :all, :conditions => { :validation_type => "bootstrapping" } ).collect{ |v| v.validation_uri }.join("\n")+"\n"
  #uri_list = Validation::Validation.all( :validation_type => "bootstrapping" ).collect{ |v| v.validation_uri }.join("\n")+"\n"
  #params[:validation_type] = "bootstrapping"
  #uri_list = Lib::DataMapperUtil.all(Validation::Validation,params).collect{ |v| v.validation_uri }.join("\n")+"\n"
  uri_list = Validation::Validation.find(:validation_type => "bootstrapping").sort.collect{|v| v.validation_uri}.join("\n") + "\n"
  
  if request.env['HTTP_ACCEPT'] =~ /text\/html/
    related_links = 
      "All validations:    "+url_for("/",:full)+"\n"+
      "Validation reports: "+url_for("/report/validation",:full)
    description = 
        "A list of all bootstrapping-validations.\n\n"+
        "Bootstrapping performs sampling with replacement to create a training dataset and test dataset from the orignial dataset.\n"+
        "Subsequently, a model is built with the training dataset and validated on the test-dataset.\n\n"+
        "Quote from R Kohavi - A study of cross-validation and bootstrap for accuracy estimation and model selection,\n"+
        "International joint Conference on artificial intelligence, 1995:\n"+
        "'Given a dataset of size n, a bootstrap sample is created by sampling n instances uniformly from the data (with replacement).\n"+
        " Since the dataset is sampled with replacement, the probability of any given instance not being chosen after n samples is (1 - 1/n)^n = e^-1 = 0.368;\n"+
        " the expected number of distinct instances from the original dataset appearing in the test set is thus 0.632n.'\n\n"+
        "To perform a bootstrapping-validation use the POST method."
    post_command = OpenTox::PostCommand.new request.url,"Perform bootstrapping-validation"
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
    post_command.attributes << OpenTox::PostAttribute.new("dataset_uri")
    post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
    post_command.attributes << OpenTox::PostAttribute.new("random_seed",false,"1","An equal random seed value ensures the excact same random dataset split.")
    content_type "text/html"
    OpenTox.text_to_html uri_list,@subjectid,related_links,description,post_command
  else
    content_type "text/uri-list"
    uri_list
  end
end

post '/training_test_split' do
  LOGGER.info "creating training test split "+params.inspect
  raise OpenTox::BadRequestError.new "dataset_uri missing" unless params[:dataset_uri].to_s.size>0
  raise OpenTox::BadRequestError.new "algorithm_uri missing" unless params[:algorithm_uri].to_s.size>0
  raise OpenTox::BadRequestError.new "prediction_feature missing" unless params[:prediction_feature].to_s.size>0
  task = OpenTox::Task.create( "Perform training test split validation", url_for("/training_test_split", :full) )  do |task| #, params
    strat = (params[:stratified].size>0 && params[:stratified]!="false" && params[:stratified]!="0") if params[:stratified]
    params.merge!( Validation::Util.train_test_dataset_split(params[:dataset_uri], params[:prediction_feature], 
      @subjectid,  strat, params[:split_ratio], params[:random_seed], OpenTox::SubTask.create(task,0,33)))
    v = Validation::Validation.create  :validation_type => "training_test_split", 
                     :training_dataset_uri => params[:training_dataset_uri], 
                     :test_dataset_uri => params[:test_dataset_uri],
                     :test_target_dataset_uri => params[:dataset_uri],
                     :prediction_feature => params[:prediction_feature],
                     :algorithm_uri => params[:algorithm_uri]
    v.subjectid = @subjectid
    v.validate_algorithm( params[:algorithm_params], OpenTox::SubTask.create(task,33,100))
    v.validation_uri
  end
  return_task(task)

end

get '/training_test_split' do
  LOGGER.info "list all training-test-split-validations, params: "+params.inspect
  #uri_list = Validation::Validation.find( :all, :conditions => { :validation_type => "training_test_split" } ).collect{ |v| v.validation_uri }.join("\n")+"\n"
  #uri_list = Validation::Validation.all( :validation_type => "training_test_split" ).collect{ |v| v.validation_uri }.join("\n")+"\n"
  #params[:validation_type] = "training_test_split"
  #uri_list = Lib::DataMapperUtil.all(Validation::Validation,params).collect{ |v| v.validation_uri }.join("\n")+"\n"
  uri_list = Validation::Validation.find(:validation_type => "training_test_split").sort.collect{|v| v.validation_uri}.join("\n") + "\n"
  
  if request.env['HTTP_ACCEPT'] =~ /text\/html/
    related_links = 
      "All validations:    "+url_for("/",:full)+"\n"+
      "Validation reports: "+url_for("/report/validation",:full)
    description = 
        "A list of all training-test-split-validations.\n"+
        "To perform a training-test-split-validation use the POST method."
    post_command = OpenTox::PostCommand.new request.url,"Perform training-test-split-validation"
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
    post_command.attributes << OpenTox::PostAttribute.new("dataset_uri")
    post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
    post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
    post_command.attributes << OpenTox::PostAttribute.new("random_seed",false,"1","An equal random seed value ensures the excact same random dataset split.")
    post_command.attributes << OpenTox::PostAttribute.new("split_ratio",false,"0.66","A split ratio of 0.66 implies that two thirds of the compounds are used for training.")
    content_type "text/html"
    OpenTox.text_to_html uri_list,@subjectid,related_links,description,post_command
  else
    content_type "text/uri-list"
    uri_list
  end
end

post '/cleanup/?' do
  LOGGER.info "validation cleanup, starting..."
  content_type "text/uri-list"
  deleted = []
  Validation::Validation.all.collect.delete_if{|val| val.finished}.each do |val|
    if OpenTox::Authorization.authorized?(val.validation_uri,"DELETE",@subjectid)
      LOGGER.debug "delete val with id:"+val.id.to_s+", finished is false"
      deleted << val.validation_uri
      val.subjectid = @subjectid
      val.delete_validation
      sleep 1 if AA_SERVER
    end
  end
  LOGGER.info "validation cleanup, deleted "+deleted.size.to_s+" validations"
  deleted.join("\n")+"\n"
end

post '/cleanup_datasets/?' do
  LOGGER.info "dataset cleanup, starting..."
  content_type "text/uri-list"
  used_datasets = Set.new
  Validation::Crossvalidation.all.each do |cv|
    used_datasets << cv.dataset_uri
  end
  Validation::Validation.all.each do |val|
    used_datasets << val.training_dataset_uri
    used_datasets << val.test_target_dataset_uri
    used_datasets << val.test_dataset_uri
    used_datasets << val.prediction_dataset_uri
  end
  deleted = []
  OpenTox::Dataset.all.each do |d|
    if !used_datasets.include?(d.uri) and OpenTox::Authorization.authorized?(d.uri,"DELETE",@subjectid)
      deleted << d.uri
      d.delete(@subjectid)
      sleep 1 if AA_SERVER
    end
  end
  LOGGER.info "dataset cleanup, deleted "+deleted.size.to_s+" datasets"
  deleted.join("\n")+"\n"
end

post '/plain_training_test_split' do
  LOGGER.info "creating pure training test split "+params.inspect
  raise OpenTox::BadRequestError.new "dataset_uri missing" unless params[:dataset_uri]
  task = OpenTox::Task.create( "Create data-split", url_for("/plain_training_test_split", :full) ) do |task|
    strat = (params[:stratified].size>0 && params[:stratified]!="false" && params[:stratified]!="0") if params[:stratified]
    result = Validation::Util.train_test_dataset_split(params[:dataset_uri], params[:prediction_feature], @subjectid,
       strat, params[:split_ratio], params[:random_seed])
    content_type "text/uri-list"
    result[:training_dataset_uri]+"\n"+result[:test_dataset_uri]+"\n"
  end
  return_task(task)
end

post '/validate_datasets' do
  task = OpenTox::Task.create( "Perform dataset validation", url_for("/validate_datasets", :full) ) do |task| #, params
    LOGGER.info "validating values "+params.inspect
    raise OpenTox::BadRequestError.new "test_dataset_uri missing" unless params[:test_dataset_uri]
    raise OpenTox::BadRequestError.new "prediction_datset_uri missing" unless params[:prediction_dataset_uri]
    params[:validation_type] = "validate_datasets" 
    
    if params[:model_uri]
      raise OpenTox::BadRequestError.new "please specify 'model_uri' or set either 'classification' or 'regression' flag" if params[:classification] or params[:regression]
      v = Validation::Validation.create params
      v.subjectid = @subjectid
      v.compute_validation_stats_with_model(nil,false,task)
    else
      raise OpenTox::BadRequestError.new "please specify 'model_uri' or 'prediction_feature'" unless params[:prediction_feature]
      raise OpenTox::BadRequestError.new "please specify 'model_uri' or 'predicted_variable'" unless params[:predicted_variable]
      raise OpenTox::BadRequestError.new "please specify 'model_uri' or set either 'classification' or 'regression' flag" unless 
            params[:classification] or params[:regression]
      predicted_variable = params.delete("predicted_variable")
      predicted_confidence = params.delete("predicted_confidence")
      feature_type = "classification" if params.delete("classification")!=nil
      feature_type = "regression" if params.delete("regression")!=nil
      v = Validation::Validation.create params  
      v.subjectid = @subjectid
      v.compute_validation_stats(feature_type,predicted_variable,predicted_confidence,nil,nil,false,task)
    end
    v.validation_uri
  end
  return_task(task)
end

get '/:id/probabilities' do
  LOGGER.info "get validation probabilities "+params.inspect
  
  begin
    validation = Validation::Validation.get(params[:id])
  rescue ActiveRecord::RecordNotFound => ex
    raise OpenTox::NotFoundError.new("Validation '#{params[:id]}' not found.")
  end
  validation.subjectid = @subjectid
  raise OpenTox::BadRequestError.new("Validation '"+params[:id].to_s+"' not finished") unless validation.finished
  raise OpenTox::BadRequestError.new("Missing params, plz give confidence and prediction") unless params[:confidence] and params[:prediction]
  props = validation.probabilities(params[:confidence].to_s.to_f,params[:prediction].to_s)
  content_type "text/x-yaml"
  props.to_yaml
end 


#get '/:id/predictions' do
#  LOGGER.info "get validation predictions "+params.inspect
#  begin
#    #validation = Validation::Validation.find(params[:id])
#    validation = Validation::Validation.get(params[:id])
#  rescue ActiveRecord::RecordNotFound => ex
#    raise OpenTox::NotFoundError.new "Validation '#{params[:id]}' not found."
#  end
#  raise OpenTox::BadRequestError.new "Validation '"+params[:id].to_s+"' not finished" unless validation.finished
#  p = validation.compute_validation_stats_with_model(nil, true)
#  case request.env['HTTP_ACCEPT'].to_s
#  when /text\/html/
#    content_type "text/html"
#    description = 
#      "The validation predictions as (yaml-)array."
#    related_links = 
#      "All validations:         "+url_for("/",:full)+"\n"+
#      "Correspoding validation: "+url_for("/"+params[:id],:full)
#    OpenTox.text_to_html p.to_array.to_yaml,@subjectid, related_links, description
#  else
#    content_type "text/x-yaml"
#    p.to_array.to_yaml
#  end
#end 

#get '/:id/:attribute' do
#  LOGGER.info "access validation attribute "+params.inspect
#  begin
#    validation = Validation::Validation.find(params[:id])
#  rescue ActiveRecord::RecordNotFound => ex
#    raise OpenTox::NotFoundError.new "Validation '#{params[:id]}' not found."
#  end
#  begin
#    raise unless validation.attribute_loaded?(params[:attribute])
#  rescue
#    raise OpenTox::BadRequestError.new "Not a validation attribute: "+params[:attribute].to_s
#  end
#  content_type "text/plain"
#  return validation.send(params[:attribute])
#end

get '/:id' do
  LOGGER.info "get validation with id "+params[:id].to_s+" '"+request.env['HTTP_ACCEPT'].to_s+"'"
#  begin
    #validation = Validation::Validation.find(params[:id])
#  rescue ActiveRecord::RecordNotFound => ex
#    raise OpenTox::NotFoundError.new "Validation '#{params[:id]}' not found."
#  end
  validation = Validation::Validation[params[:id]]
  raise OpenTox::NotFoundError.new "Validation '#{params[:id]}' not found." unless validation
  
  case request.env['HTTP_ACCEPT'].to_s
  when "application/rdf+xml"
    content_type "application/rdf+xml"
    validation.to_rdf
  when /text\/html/
    content_type "text/html"
    description = 
      "A validation resource."
    related_links = 
      "Search for corresponding report: "+url_for("/report/validation?validation="+validation.validation_uri,:full)+"\n"+
      "Get validation predictions:      "+url_for("/"+params[:id]+"/predictions",:full)+"\n"+
      "All validations:                 "+url_for("/",:full)+"\n"+
      "All validation reports:          "+url_for("/report/validation",:full)
    OpenTox.text_to_html validation.to_rdf_yaml,@subjectid,related_links,description
  when "application/serialize"
    content_type "application/serialize"
    validation.inspect # to load all the stuff
    validation.to_yaml
  else #default is yaml 
    content_type "application/x-yaml"
    validation.to_rdf_yaml
  end
end

delete '/:id' do
  LOGGER.info "delete validation with id "+params[:id].to_s
#  begin
    #validation = Validation::Validation.find(params[:id])
#  rescue ActiveRecord::RecordNotFound => ex
#    raise OpenTox::NotFoundError.new "Validation '#{params[:id]}' not found."
#  end
  validation = Validation::Validation.get(params[:id])
  validation.subjectid = @subjectid
  raise OpenTox::NotFoundError.new "Validation '#{params[:id]}' not found." unless validation
  content_type "text/plain"
  validation.delete_validation
end