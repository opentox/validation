[ 'rubygems', 'sinatra' ].each do |lib|
  require lib
end

require './lib/dataset_cache.rb'
require './validation/validation_service.rb'

class Validation::Application < OpenTox::Application
  
    helpers do
      def check_stratified(params)
        params[:stratified] = "false" unless params[:stratified]
        bad_request_error "stratified != true|false|super, is #{params[:stratified]}" unless
          params[:stratified]=~/true|false|super/
      end

      def filter_validation(validation, params)
        if (params[:min_confidence] or params[:min_num_predictions] or params[:max_num_predictions])
          min_confidence = params[:min_confidence] ? params[:min_confidence].to_f : nil
          min_num_predictions = params[:min_num_predictions] ? params[:min_num_predictions].to_i : nil
          max_num_predictions = params[:max_num_predictions] ? params[:max_num_predictions].to_i : nil
          validation.filter_predictions(min_confidence,min_num_predictions,max_num_predictions)
        end
      end
    end
    
    before do
      $url_provider = self
    end
    
    # for service check
    head '/validation/?' do
      #$logger.debug "Validation service is running."
    end
    
    get '/validation/crossvalidation/?' do
      $logger.info "list all crossvalidations "+params.inspect
      model_uri = params.delete("model") || params.delete("model_uri")
      if model_uri
        model = OpenTox::Model::Generic.find(model_uri)
        params[:algorithm] = model.metadata[RDF::OT.algorithm]
        params[:dataset] = model.metadata[RDF::OT.trainingDataset]
      end
      uri_list = Lib::OhmUtil.find( Validation::Crossvalidation, params ).sort.collect{|v| v.crossvalidation_uri}.join("\n") + "\n"
      if request.env['HTTP_ACCEPT'] =~ /text\/html/
        related_links = 
          "Single validations:             "+to("/validation/",:full)+"\n"+
          "Leave-one-out crossvalidations: "+to("/validation/crossvalidation/loo",:full)+"\n"+
          "Crossvalidation reports:        "+to("/validation/report/crossvalidation",:full)
        description = 
          "A list of all crossvalidations.\n"+
          "Use the POST method to perform a crossvalidation."
        # post_command = OpenTox::PostCommand.new request.url,"Perform crossvalidation"
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("dataset_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
        # post_command.attributes << OpenTox::PostAttribute.new("num_folds",false,"10")
        # post_command.attributes << OpenTox::PostAttribute.new("random_seed",false,"1","An equal random seed value ensures the excact same random dataset split.")
        # post_command.attributes << OpenTox::PostAttribute.new("stratified",false,"false","Stratification ensures an equal class-value spread in folds.")
        content_type "text/html"
        uri_list.to_html(related_links,description)#,post_command
      else
        content_type "text/uri-list"
        uri_list
      end
    end
    
    post '/validation/crossvalidation/?' do
      $logger.info "creating crossvalidation "+params.inspect
      bad_request_error "dataset_uri missing" unless params[:dataset_uri].to_s.size>0
      bad_request_error "algorithm_uri missing" unless params[:algorithm_uri].to_s.size>0
      bad_request_error "prediction_feature missing" unless params[:prediction_feature].to_s.size>0
      bad_request_error "illegal param-value num_folds: '"+params[:num_folds].to_s+"', must be integer >1" unless params[:num_folds]==nil or 
        params[:num_folds].to_i>1
      check_stratified(params)
      
      task = OpenTox::Task.run( "Perform crossvalidation", to("/validation/crossvalidation", :full) ) do |task| #, params
        cv_params = { :dataset_uri => params[:dataset_uri],  
                      :algorithm_uri => params[:algorithm_uri],
                      :algorithm_params => params[:algorithm_params],
                      :prediction_feature => params[:prediction_feature],
                      :stratified => params[:stratified],
                      :loo => "false" }
        [ :num_folds, :random_seed ].each{ |sym| cv_params[sym] = params[sym] if params[sym] }
        cv = Validation::Crossvalidation.create cv_params
        cv.perform_cv( OpenTox::SubTask.create(task,0,95) )
        # computation of stats is cheap as dataset are already loaded into the memory
        Validation::Validation.from_cv_statistics( cv.id, OpenTox::SubTask.create(task,95,100) )
        cv.crossvalidation_uri
      end
      return_task(task)
    end
    
    post '/validation/crossvalidation/cleanup/?' do
      $logger.info "crossvalidation cleanup, starting..."
      content_type "text/uri-list"
      deleted = []
      Validation::Crossvalidation.all.collect.select{|cv| !cv.finished}.each do |cv|
        if OpenTox::Authorization.authorized?(cv.crossvalidation_uri,"DELETE")
          $logger.debug "delete cv with id:"+cv.id.to_s+", finished is false"
          deleted << cv.crossvalidation_uri
          cv.delete_crossvalidation
          sleep 1 if $aa[:uri]
        end
      end
      $logger.info "crossvalidation cleanup, deleted "+deleted.size.to_s+" cvs"
      deleted.join("\n")+"\n"
    end
    
    post '/validation/crossvalidation/loo/?' do
      $logger.info "creating loo-crossvalidation "+params.inspect
      bad_request_error "dataset_uri missing" unless params[:dataset_uri].to_s.size>0
      bad_request_error "algorithm_uri missing" unless params[:algorithm_uri].to_s.size>0
      bad_request_error "prediction_feature missing" unless params[:prediction_feature].to_s.size>0
      bad_request_error "illegal param: num_folds, stratified, random_seed not allowed for loo-crossvalidation" if params[:num_folds] or 
        params[:stratified] or (params[:random_seed] and !params[:skip_ratio])
      task = OpenTox::Task.run( "Perform loo-crossvalidation", to("/validation/crossvalidation/loo", :full) ) do |task| #, params
        cv_params = { :dataset_uri => params[:dataset_uri],
                      :algorithm_params => params[:algorithm_params],
                      :prediction_feature => params[:prediction_feature],  
                      :algorithm_uri => params[:algorithm_uri],
                      :loo => (params[:loo]=="uniq" ? "uniq" : "true"),
                      :random_seed => params[:random_seed]}
        cv = Validation::Crossvalidation.create cv_params
        cv.perform_cv( OpenTox::SubTask.create(task,0,95), (params[:skip_ratio] ? params[:skip_ratio].to_f : nil))
        # computation of stats is cheap as dataset are already loaded into the memory
        Validation::Validation.from_cv_statistics( cv.id, OpenTox::SubTask.create(task,95,100) )
        #cv.clean_loo_files( !(params[:algorithm_params] && params[:algorithm_params] =~ /feature_dataset_uri/) )
        cv.crossvalidation_uri
      end
      return_task(task)
    end
    
    get '/validation/crossvalidation/loo/?' do
      $logger.info "list all crossvalidations"
      params[:loo]="true"
      uri_list = Lib::OhmUtil.find( Validation::Crossvalidation, params ).sort.collect{|v| v.crossvalidation_uri}.join("\n") + "\n"
      if request.env['HTTP_ACCEPT'] =~ /text\/html/
        related_links = 
          "Single validations:      "+to("/validation/",:full)+"\n"+
          "All crossvalidations:    "+to("/validation/crossvalidation",:full)+"\n"+
          "Crossvalidation reports: "+to("/validation/report/crossvalidation",:full)
        description = 
          "A list of all leave one out crossvalidations.\n"+
          "Use the POST method to perform a crossvalidation."
        # post_command = OpenTox::PostCommand.new request.url,"Perform leave-one-out-crossvalidation"
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("dataset_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
        content_type "text/html"
        uri_list.to_html related_links,description#,post_command
      else
        content_type "text/uri-list"
        uri_list
      end
      
    end
    
    get '/validation/crossvalidation/:id' do
      $logger.info "get crossvalidation with id "+params[:id].to_s
    #  begin
    #    #crossvalidation = Validation::Crossvalidation.find(params[:id])
    #  rescue ActiveRecord::RecordNotFound => ex
    #    resource_not_found_error "Crossvalidation '#{params[:id]}' not found."
    #  end
      crossvalidation = Validation::Crossvalidation[params[:id]]
      resource_not_found_error "Crossvalidation '#{params[:id]}' not found." unless crossvalidation
      
      case request.env['HTTP_ACCEPT'].to_s
      when "application/rdf+xml"
        content_type "application/rdf+xml"
        crossvalidation.to_rdf
      when /text\/html/
        related_links = 
          "Search for corresponding cv report:  "+to("/validation/report/crossvalidation?crossvalidation="+crossvalidation.crossvalidation_uri,:full)+"\n"+
          "Statistics for this crossvalidation: "+to("/validation/crossvalidation/"+params[:id]+"/statistics",:full)+"\n"+
          "Predictions of this crossvalidation: "+to("/validation/crossvalidation/"+params[:id]+"/predictions",:full)+"\n"+
          "All crossvalidations:                "+to("/validation/crossvalidation",:full)+"\n"+
          "All crossvalidation reports:         "+to("/validation/report/crossvalidation",:full)
        description = 
            "A crossvalidation resource."
        content_type "text/html"
        crossvalidation.to_rdf_yaml.to_html related_links,description
      when "application/serialize"
        content_type "application/serialize"
        crossvalidation.inspect # to load all the stuff
        crossvalidation.to_yaml
      when /application\/x-yaml|\*\/\*/
        content_type "application/x-yaml"
        crossvalidation.to_rdf_yaml
      else
        bad_request_error "MIME type '"+request.env['HTTP_ACCEPT'].to_s+"' not supported, valid Accept-Headers: \"application/rdf+xml\", \"application/x-yaml\", \"text/html\"."
      end
    end
    
    get '/validation/crossvalidation/:id/statistics' do
      
      $logger.info "get crossvalidation statistics for crossvalidation with id "+params[:id].to_s
      v = Validation::Validation.from_cv_statistics( params[:id] )
      filter_validation(v,params)
      case request.env['HTTP_ACCEPT'].to_s
      when /text\/html/
        related_links = 
           "The corresponding crossvalidation resource: "+to("/validation/crossvalidation/"+params[:id],:full)
        description = 
           "The averaged statistics for the crossvalidation."
        content_type "text/html"
        v.to_rdf_yaml.to_html related_links,description
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
    
    get '/validation/crossvalidation/:id/statistics/probabilities' do
      
      $logger.info "get crossvalidation statistics for crossvalidation with id "+params[:id].to_s
      bad_request_error("Missing params, plz give confidence and prediction") unless params[:confidence] and params[:prediction]
      v = Validation::Validation.from_cv_statistics( params[:id] )
      props = v.probabilities(params[:confidence].to_s.to_f,params[:prediction].to_s)
      content_type "text/x-yaml"
      props.to_yaml
    end

    get '/validation/crossvalidation/:id/prediction_data' do
      Validation::Validation.from_cv_statistics( params[:id] ).prediction_data.to_yaml
    end
    
    delete '/validation/crossvalidation/:id/?' do
      $logger.info "delete crossvalidation with id "+params[:id].to_s
      content_type "text/plain"
    #  begin
        #crossvalidation = Validation::Crossvalidation.find(params[:id])
    #  rescue ActiveRecord::RecordNotFound => ex
    #    resource_not_found_error "Crossvalidation '#{params[:id]}' not found."
    #  end
    #  Validation::Crossvalidation.delete(params[:id])
      
      cv = Validation::Crossvalidation[params[:id]]
      resource_not_found_error "Crossvalidation '#{params[:id]}' not found." unless cv
      cv.delete_crossvalidation
    end
    
    #get '/validation/crossvalidation/:id/validations' do
    #  $logger.info "get all validations for crossvalidation with id "+params[:id].to_s
    #  begin
    #    crossvalidation = Validation::Crossvalidation.find(params[:id])
    #  rescue ActiveRecord::RecordNotFound => ex
    #    resource_not_found_error "Crossvalidation '#{params[:id]}' not found."
    #  end
    #  content_type "text/uri-list"
    #  Validation::Validation.find( :all, :conditions => { :crossvalidation_id => params[:id] } ).collect{ |v| v.validation_uri.to_s }.join("\n")+"\n"
    #end
    
    #get '/validation/crossvalidation/:id/predictions' do
    #  $logger.info "get predictions for crossvalidation with id "+params[:id].to_s
    #  begin
    #    #crossvalidation = Validation::Crossvalidation.find(params[:id])
    #    crossvalidation = Validation::Crossvalidation[params[:id]]
    #  rescue ActiveRecord::RecordNotFound => ex
    #    resource_not_found_error "Crossvalidation '#{params[:id]}' not found."
    #  end
    #  bad_request_error "Crossvalidation '"+params[:id].to_s+"' not finished" unless crossvalidation.finished
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
    #      "All crossvalidations:         "+to("/validation/crossvalidation",:full)+"\n"+
    #      "Correspoding crossvalidation: "+to("/validation/crossvalidation/"+params[:id],:full)
    #    OpenTox.text_to_html p,@subjectid, related_links, description
    #  else
    #    content_type "text/x-yaml"
    #    p
    #  end
    #end
    
    get '/validation/?' do
      
      $logger.info "list all validations, params: "+params.inspect+" #{Validation::Validation}"
      uri_list = Lib::OhmUtil.find( Validation::Validation, params ).sort.collect{|v| v.validation_uri}.join("\n") + "\n"
      if request.env['HTTP_ACCEPT'] =~ /text\/html/
        related_links = 
          "To perform a validation:\n"+
          "* "+to("/validation/test_set_validation",:full)+"\n"+
          "* "+to("/validation/training_test_validation",:full)+"\n"+
          "* "+to("/validation/bootstrapping",:full)+"\n"+
          "* "+to("/validation/training_test_split",:full)+"\n"+
          "* "+to("/validation/crossvalidation",:full)+"\n"+
          "Validation reporting:            "+to("/validation/report",:full)+"\n"+
          "REACH relevant reporting:        "+to("/validation/reach_report",:full)+"\n"+
          "Examples for using this service: "+to("/validation/examples",:full)+"\n"
        description = 
            "A validation web service for the OpenTox project ( http://opentox.org ).\n"+
            "In the root directory (this is where you are now), a list of all validation resources is returned."
        content_type "text/html"
        uri_list.to_html related_links,description
      else
        content_type "text/uri-list"
        uri_list
      end
    end
    
    post '/validation/?' do
      bad_request_error "Post not supported, to perfom a validation use '/test_set_validation', '/training_test_validation', 'bootstrapping', 'training_test_split'"
    end
    
    post '/validation/test_set_validation' do
      $logger.info "creating test-set-validation "+params.inspect
      if params[:model_uri].to_s.size>0 and params[:test_dataset_uri].to_s.size>0 and 
        params[:training_dataset_uri].to_s.size==0 and params[:algorithm_uri].to_s.size==0
        task = OpenTox::Task.run( "Perform test-set-validation", to("/validation/", :full) ) do |task| #, params
          v = Validation::Validation.create :validation_type => "test_set_validation", 
                           :model_uri => params[:model_uri], 
                           :test_dataset_uri => params[:test_dataset_uri],
                           :prediction_feature => params[:prediction_feature]
          v.validate_model( task )
          v.validation_uri
        end
        return_task(task)
      else
        bad_request_error "illegal parameters, pls specify model_uri and test_dataset_uri\n"+
          "params given: "+params.inspect
      end
    end
    
    get '/validation/test_set_validation' do
      $logger.info "list all test-set-validations, params: "+params.inspect
      
      #uri_list = Validation::Validation.find( :all, :conditions => { :validation_type => "test_set_validation" } ).collect{ |v| v.validation_uri }.join("\n")+"\n"
      #uri_list = Validation::Validation.all( :validation_type => "test_set_validation" ).collect{ |v| v.validation_uri }.join("\n")+"\n"
      #params[:validation_type] = "test_set_validation"
      #uri_list = Lib::DataMapperUtil.all(Validation::Validation,params).collect{ |v| v.validation_uri }.join("\n")+"\n"
      uri_list = Validation::Validation.find(:validation_type => "test_set_validation").sort.collect{|v| v.validation_uri}.join("\n") + "\n"
      
      if request.env['HTTP_ACCEPT'] =~ /text\/html/
        related_links = 
          "All validations:    "+to("/validation/",:full)+"\n"+
          "Validation reports: "+to("/validation/report/validation",:full)
        description = 
            "A list of all test-set-validations.\n"+
            "To perform a test-set-validation use the POST method."
        # post_command = OpenTox::PostCommand.new request.url,"Perform test-set-validation"
        # post_command.attributes << OpenTox::PostAttribute.new("model_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("test_dataset_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("prediction_feature",false,nil,"Default is 'dependentVariables' of the model.")
        content_type "text/html"
        uri_list.to_html related_links,description#,post_command
      else
        content_type "text/uri-list"
        uri_list
      end
    end
    
    post '/validation/training_test_validation/?' do
      $logger.info "creating training-test-validation "+params.inspect
      if params[:algorithm_uri].to_s.size>0 and params[:training_dataset_uri].to_s.size>0 and 
        params[:test_dataset_uri].to_s.size>0 and params[:prediction_feature].to_s.size>0 and params[:model_uri].to_s.size==0
        task = OpenTox::Task.run( "Perform training-test-validation", to("/validation/", :full) ) do |task| #, params
          v = Validation::Validation.create :validation_type => "training_test_validation", 
                            :algorithm_uri => params[:algorithm_uri],
                            :algorithm_params => params[:algorithm_params],
                            :training_dataset_uri => params[:training_dataset_uri], 
                            :test_dataset_uri => params[:test_dataset_uri],
                            :prediction_feature => params[:prediction_feature]
          v.validate_algorithm( task ) 
          v.validation_uri
        end
        return_task(task)
      else
        bad_request_error "illegal parameters, pls specify algorithm_uri, training_dataset_uri, test_dataset_uri, prediction_feature\n"+
            "params given: "+params.inspect
      end
    end
    
    get '/validation/training_test_validation' do
      $logger.info "list all training-test-validations, params: "+params.inspect
      #uri_list = Validation::Validation.find( :all, :conditions => { :validation_type => "training_test_validation" } ).collect{ |v| v.validation_uri }.join("\n")+"\n"
      #uri_list = Validation::Validation.all( :validation_type => "training_test_validation" ).collect{ |v| v.validation_uri }.join("\n")+"\n"
      #params[:validation_type] = "training_test_validation"
      #uri_list = Lib::DataMapperUtil.all(Validation::Validation,params).collect{ |v| v.validation_uri }.join("\n")+"\n"
      uri_list = Validation::Validation.find(:validation_type => "training_test_validation").sort.collect{|v| v.validation_uri}.join("\n") + "\n"
      
      if request.env['HTTP_ACCEPT'] =~ /text\/html/
        related_links = 
          "All validations:    "+to("/validation/",:full)+"\n"+
          "Validation reports: "+to("/validation/report/validation",:full)
        description = 
            "A list of all training-test-validations.\n"+
            "To perform a training-test-validation use the POST method."
        # post_command = OpenTox::PostCommand.new request.url,"Perform training-test-validation"
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("training_dataset_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("test_dataset_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
        content_type "text/html"
        uri_list.to_html related_links,description#,post_command
      else
        content_type "text/uri-list"
        uri_list
      end
    end
    
    post '/validation/bootstrapping' do
      $logger.info "performing bootstrapping validation "+params.inspect
      bad_request_error "dataset_uri missing" unless params[:dataset_uri].to_s.size>0
      bad_request_error "algorithm_uri missing" unless params[:algorithm_uri].to_s.size>0
      bad_request_error "prediction_feature missing" unless params[:prediction_feature].to_s.size>0
      task = OpenTox::Task.run( "Perform bootstrapping validation", to("/validation/bootstrapping", :full) ) do |task| #, params
        params.merge!( Validation::Util.bootstrapping( params[:dataset_uri], 
          params[:prediction_feature],
          params[:random_seed], OpenTox::SubTask.create(task,0,33)) )
        $logger.info "params after bootstrapping: "+params.inspect
        v = Validation::Validation.create :validation_type => "bootstrapping", 
                         :prediction_feature => params[:prediction_feature],
                         :algorithm_uri => params[:algorithm_uri],
                         :algorithm_params => params[:algorithm_params],
                         :training_dataset_uri => params[:training_dataset_uri], 
                         :test_dataset_uri => params[:test_dataset_uri]
        v.validate_algorithm( OpenTox::SubTask.create(task,33,100))
        v.validation_uri
      end
      return_task(task)
    end
    
    get '/validation/bootstrapping' do
      $logger.info "list all bootstrapping-validations, params: "+params.inspect
      #uri_list = Validation::Validation.find( :all, :conditions => { :validation_type => "bootstrapping" } ).collect{ |v| v.validation_uri }.join("\n")+"\n"
      #uri_list = Validation::Validation.all( :validation_type => "bootstrapping" ).collect{ |v| v.validation_uri }.join("\n")+"\n"
      #params[:validation_type] = "bootstrapping"
      #uri_list = Lib::DataMapperUtil.all(Validation::Validation,params).collect{ |v| v.validation_uri }.join("\n")+"\n"
      uri_list = Validation::Validation.find(:validation_type => "bootstrapping").sort.collect{|v| v.validation_uri}.join("\n") + "\n"
      
      if request.env['HTTP_ACCEPT'] =~ /text\/html/
        related_links = 
          "All validations:    "+to("/validation/",:full)+"\n"+
          "Validation reports: "+to("/validation/report/validation",:full)
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
        # post_command = OpenTox::PostCommand.new request.url,"Perform bootstrapping-validation"
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("dataset_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
        # post_command.attributes << OpenTox::PostAttribute.new("random_seed",false,"1","An equal random seed value ensures the excact same random dataset split.")
        content_type "text/html"
        uri_list.to_html related_links,description#,post_command
      else
        content_type "text/uri-list"
        uri_list
      end
    end
    
    post '/validation/training_test_split' do
      $logger.info "creating training test split "+params.inspect
      bad_request_error "dataset_uri missing" unless params[:dataset_uri].to_s.size>0
      bad_request_error "algorithm_uri missing" unless params[:algorithm_uri].to_s.size>0
      bad_request_error "prediction_feature missing" unless params[:prediction_feature].to_s.size>0
      check_stratified(params)
      task = OpenTox::Task.run( "Perform training test split validation", uri("/validation/training_test_split"))  do |task| #, params
        $logger.debug "performing train test split"
        params.merge!( Validation::Util.train_test_dataset_split(to("/validation/training_test_split", :full), params[:dataset_uri], 
          (params[:stratified].to_s=~/true/ ? params[:prediction_feature] : nil), params[:stratified], params[:split_ratio], 
          params[:random_seed], OpenTox::SubTask.create(task,0,33)))
        $logger.debug "creating validation"  
        v = Validation::Validation.create :validation_type => "training_test_split", 
                         :training_dataset_uri => params[:training_dataset_uri], 
                         :test_dataset_uri => params[:test_dataset_uri],
                         :prediction_feature => params[:prediction_feature],
                         :algorithm_uri => params[:algorithm_uri],
                         :algorithm_params => params[:algorithm_params]
        $logger.debug "created validation, validating algorithm"
        v.validate_algorithm( OpenTox::SubTask.create(task,33,100))
        v.validation_uri
      end
      return_task(task)
    
    end
    
    get '/validation/training_test_split' do
      $logger.info "list all training-test-split-validations, params: "+params.inspect
      #uri_list = Validation::Validation.find( :all, :conditions => { :validation_type => "training_test_split" } ).collect{ |v| v.validation_uri }.join("\n")+"\n"
      #uri_list = Validation::Validation.all( :validation_type => "training_test_split" ).collect{ |v| v.validation_uri }.join("\n")+"\n"
      #params[:validation_type] = "training_test_split"
      #uri_list = Lib::DataMapperUtil.all(Validation::Validation,params).collect{ |v| v.validation_uri }.join("\n")+"\n"
      uri_list = Validation::Validation.find(:validation_type => "training_test_split").sort.collect{|v| v.validation_uri}.join("\n") + "\n"
      
      if request.env['HTTP_ACCEPT'] =~ /text\/html/
        related_links = 
          "All validations:    "+to("/validation/",:full)+"\n"+
          "Validation reports: "+to("/validation/report/validation",:full)
        description = 
            "A list of all training-test-split-validations.\n"+
            "To perform a training-test-split-validation use the POST method."
        # post_command = OpenTox::PostCommand.new request.url,"Perform training-test-split-validation"
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("dataset_uri")
        # post_command.attributes << OpenTox::PostAttribute.new("prediction_feature")
        # post_command.attributes << OpenTox::PostAttribute.new("algorithm_params",false,nil,"Params used for model building, separate with ';', example: param1=v1;param2=v2")
        # post_command.attributes << OpenTox::PostAttribute.new("random_seed",false,"1","An equal random seed value ensures the excact same random dataset split.")
        # post_command.attributes << OpenTox::PostAttribute.new("split_ratio",false,"0.66","A split ratio of 0.66 implies that two thirds of the compounds are used for training.")
        content_type "text/html"
        uri_list.to_html related_links,description#,post_command
      else
        content_type "text/uri-list"
        uri_list
      end
    end
    
    post '/validation/cleanup/?' do
      $logger.info "validation cleanup, starting..."
      content_type "text/uri-list"
      deleted = []
      Validation::Validation.all.collect.select{|val| !val.finished}.each do |val|
        if OpenTox::Authorization.authorized?(val.validation_uri,"DELETE")
          $logger.debug "delete val with id:"+val.id.to_s+", finished is false"
          deleted << val.validation_uri
          val.delete_validation
          sleep 1 if $aa[:uri]
        end
      end
      $logger.info "validation cleanup, deleted "+deleted.size.to_s+" validations"
      deleted.join("\n")+"\n"
    end
    
    post '/validation/cleanup_datasets/?' do
      $logger.info "dataset cleanup, starting..."
      content_type "text/uri-list"
      used_datasets = Set.new
      Validation::Crossvalidation.all.each do |cv|
        used_datasets << cv.dataset_uri
      end
      Validation::Validation.all.each do |val|
        used_datasets << val.training_dataset_uri
        used_datasets << val.test_dataset_uri
        used_datasets << val.prediction_dataset_uri
      end
      deleted = []
      OpenTox::Dataset.all.each do |d|
        if !used_datasets.include?(d.uri) and OpenTox::Authorization.authorized?(d.uri,"DELETE")
          deleted << d.uri
          d.delete
          sleep 1 if $aa[:uri]
        end
      end
      $logger.info "dataset cleanup, deleted "+deleted.size.to_s+" datasets"
      deleted.join("\n")+"\n"
    end
    
    post '/validation/plain_training_test_split' do
      $logger.info "creating pure training test split "+params.inspect
      bad_request_error "dataset_uri missing" unless params[:dataset_uri]
      check_stratified(params)
      task = OpenTox::Task.run( "Create data-split", to("/validation/plain_training_test_split", :full) ) do |task|
        result = Validation::Util.train_test_dataset_split(to("/validation/plain_training_test_split", :full), params[:dataset_uri], params[:prediction_feature], 
          params[:stratified], params[:split_ratio], params[:random_seed], task)
        content_type "text/uri-list"
        result[:training_dataset_uri]+"\n"+result[:test_dataset_uri]+"\n"
      end
      return_task(task)
    end
    
    post '/validation/validate_datasets' do
      task = OpenTox::Task.run( "Perform dataset validation", to("/validation/validate_datasets", :full) ) do |task| #, params
        $logger.info "validating values "+params.inspect
        bad_request_error "test_dataset_uri missing" unless params[:test_dataset_uri]
        bad_request_error "prediction_datset_uri missing" unless params[:prediction_dataset_uri]
        params[:validation_type] = "validate_datasets" 
        
        if params[:model_uri]
          bad_request_error "please specify 'model_uri' or set either 'classification' or 'regression' flag" if params[:classification] or params[:regression]
          v = Validation::Validation.create params
          v.compute_validation_stats_with_model(nil,false,task)
        else
          bad_request_error "please specify 'model_uri' or 'prediction_feature'" unless params[:prediction_feature]
          bad_request_error "please specify 'model_uri' or 'predicted_variable'" unless params[:predicted_variable]
          bad_request_error "please specify 'model_uri' or set either 'classification' or 'regression' flag" unless 
                params[:classification] or params[:regression]
          predicted_variable = params.delete("predicted_variable")
          predicted_confidence = params.delete("predicted_confidence")
          feature_type = "classification" if params.delete("classification")!=nil
          feature_type = "regression" if params.delete("regression")!=nil
          v = Validation::Validation.create params  
          v.compute_prediction_data(feature_type,predicted_variable,predicted_confidence,v.prediction_feature,nil,task)
          v.compute_validation_stats()#feature_type,predicted_variable,predicted_confidence,nil,nil,false,task)
        end
        v.validation_uri
      end
      return_task(task)
    end
    
    get '/validation/:id/probabilities' do
      $logger.info "get validation probabilities "+params.inspect
      
      begin
        validation = Validation::Validation[params[:id]]
      rescue ActiveRecord::RecordNotFound => ex
        resource_not_found_error("Validation '#{params[:id]}' not found.")
      end
      bad_request_error("Validation '"+params[:id].to_s+"' not finished") unless validation.finished
      bad_request_error("Missing params, plz give confidence and prediction") unless params[:confidence] and params[:prediction]
      props = validation.probabilities(params[:confidence].to_s.to_f,params[:prediction].to_s)
      content_type "text/x-yaml"
      props.to_yaml
    end 
    
    
    #get '/validation/:id/predictions' do
    #  $logger.info "get validation predictions "+params.inspect
    #  begin
    #    #validation = Validation::Validation.find(params[:id])
    #    validation = Validation::Validation[params[:id]]
    #  rescue ActiveRecord::RecordNotFound => ex
    #    resource_not_found_error "Validation '#{params[:id]}' not found."
    #  end
    #  bad_request_error "Validation '"+params[:id].to_s+"' not finished" unless validation.finished
    #  p = validation.compute_validation_stats_with_model(nil, true)
    #  case request.env['HTTP_ACCEPT'].to_s
    #  when /text\/html/
    #    content_type "text/html"
    #    description = 
    #      "The validation predictions as (yaml-)array."
    #    related_links = 
    #      "All validations:         "+to("/validation/",:full)+"\n"+
    #      "Correspoding validation: "+to("/validation/"+params[:id],:full)
    #    OpenTox.text_to_html p.to_array.to_yaml,@subjectid, related_links, description
    #  else
    #    content_type "text/x-yaml"
    #    p.to_array.to_yaml
    #  end
    #end 
    
    #get '/validation/:id/:attribute' do
    #  $logger.info "access validation attribute "+params.inspect
    #  begin
    #    validation = Validation::Validation.find(params[:id])
    #  rescue ActiveRecord::RecordNotFound => ex
    #    resource_not_found_error "Validation '#{params[:id]}' not found."
    #  end
    #  begin
    #    internal_server_error unless validation.attribute_loaded?(params[:attribute])
    #  rescue
    #    bad_request_error "Not a validation attribute: "+params[:attribute].to_s
    #  end
    #  content_type "text/plain"
    #  return validation.send(params[:attribute])
    #end
    
    get '/validation/:id' do
      $logger.info "get validation with id "+params[:id].to_s+" '"+request.env['HTTP_ACCEPT'].to_s+"'"
    #  begin
        #validation = Validation::Validation.find(params[:id])
    #  rescue ActiveRecord::RecordNotFound => ex
    #    resource_not_found_error "Validation '#{params[:id]}' not found."
    #  end
      validation = Validation::Validation[params[:id]]
      resource_not_found_error "Validation '#{params[:id]}' not found." unless validation
      filter_validation(validation,params)
       
      case request.env['HTTP_ACCEPT'].to_s
      when "application/rdf+xml"
        content_type "application/rdf+xml"
        validation.to_rdf
      when /text\/html/
        content_type "text/html"
        description = 
          "A validation resource."
        related_links = 
          "Search for corresponding report: "+to("/validation/report/validation?validation="+validation.validation_uri,:full)+"\n"+
          "Get validation predictions:      "+to("/validation/"+params[:id]+"/predictions",:full)+"\n"+
          "All validations:                 "+to("/validation/",:full)+"\n"+
          "All validation reports:          "+to("/validation/report/validation",:full)
        validation.to_rdf_yaml.to_html related_links,description
      when "application/serialize"
        content_type "application/serialize"
        validation.inspect # to load all the stuff
        validation.to_yaml
      else #default is yaml 
        content_type "application/x-yaml"
        validation.to_rdf_yaml
      end
    end
    
    delete '/validation/:id' do
      $logger.info "delete validation with id "+params[:id].to_s
    #  begin
        #validation = Validation::Validation.find(params[:id])
    #  rescue ActiveRecord::RecordNotFound => ex
    #    resource_not_found_error "Validation '#{params[:id]}' not found."
    #  end
      validation = Validation::Validation[params[:id]]
      resource_not_found_error "Validation '#{params[:id]}' not found." unless validation
      content_type "text/plain"
      validation.delete_validation
    end 

end
