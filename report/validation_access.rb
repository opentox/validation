require "./lib/validation_db.rb"

# = Reports::ValidationDB
# 
# connects directly to the validation db, overwirte with restclient calls 
# if reports/reach reports are seperated from validation someday
#  
class Reports::ValidationDB
  
  @@tmp_resources = []
  
  def same_service?(uri)
    self_uri = URI.parse($url_provider.url)
    val_uri = URI.parse(uri)
    self_uri.host == val_uri.host && self_uri.port == val_uri.port
  end
  
  def resolve_cv_uris(validation_uris, identifier)
    res = {}
    count = 0
    validation_uris.each do |u|
      
      if u.to_s =~ /.*\/crossvalidation\/[0-9]+/
        cv = nil
        cv_id = u.split("/")[-1].to_i
        val_uris = nil
        
        if same_service?u
          unauthorized_error "Not authorized: GET "+u.to_s if
            $aa[:uri] and !OpenTox::Authorization.authorized?(u,"GET")
          Ohm.connect(:thread_safe => true, :port => 6379)
          cv = Validation::Crossvalidation[cv_id]
          resource_not_found_error "crossvalidation with id "+cv_id.to_s+" not found" unless cv
          bad_request_error("crossvalidation with id '"+cv_id.to_s+"' not finished") unless cv.finished
          #res += Validation::Validation.find( :all, :conditions => { :crossvalidation_id => cv_id } ).collect{|v| v.validation_uri.to_s}
          val_uris = Validation::Validation.find( :crossvalidation_id => cv_id, :validation_type => "crossvalidation" ).collect{|v| v.validation_uri.to_s}
        else
          val_base_uri = u.gsub(/\/crossvalidation\/[0-9]+/,"")
          val_uris = OpenTox::RestClientWrapper.get( val_base_uri+"?crossvalidation_id="+cv_id.to_s+"&validation_type=crossvalidation",nil,{:accept => "text/uri-list" }).split("\n")
        end
        
        val_uris.each do |v_uri|
          res[v_uri] = identifier ? identifier[count] : nil
        end
      else
        res[u.to_s] = identifier ? identifier[count] : nil
      end
      count += 1
    end
    res
  end
  
  def init_validation(validation, uri, filter_params)
    
    bad_request_error "not a validation uri: "+uri.to_s unless uri =~ /\/[0-9]+$/
    validation_id = uri.split("/")[-1]
    bad_request_error "invalid validation id "+validation_id.to_s unless validation_id!=nil and 
      (validation_id.to_i > 0 || validation_id.to_s=="0" )
     
    v = nil
    
    if same_service? uri
      unauthorized_error "Not authorized: GET "+uri.to_s if
        $aa[:uri] and !OpenTox::Authorization.authorized?(uri,"GET")
      Ohm.connect(:thread_safe => true, :port => 6379)
      v = Validation::Validation[validation_id]
    else
      v = YAML::load(OpenTox::RestClientWrapper.get uri,nil,{:accept=>"application/serialize"})
    end
    #v.subjectid = subjectid
    v.filter_predictions(filter_params[:min_confidence], filter_params[:min_num_predictions], filter_params[:max_num_predictions]) if 
      filter_params
    
    resource_not_found_error "validation with id "+validation_id.to_s+" not found" unless v
    bad_request_error "validation with id "+validation_id.to_s+" is not finished yet" unless v.finished
    (Validation::VAL_PROPS + Validation::VAL_CV_PROPS).each do |p|
      validation.send("#{p.to_s}=".to_sym, v.send(p))
    end
    
    # set uris manually, in case external validation is used
    validation.validation_uri = uri 
    validation.crossvalidation_uri = uri.gsub(/\/[0-9]+/,"")+"/crossvalidation/"+validation.crossvalidation_id if validation.crossvalidation_id!=nil
    
    {:classification_statistics => Validation::VAL_CLASS_PROPS, 
     :regression_statistics => Validation::VAL_REGR_PROPS}.each do |subset_name,subset_props|
      subset = v.send(subset_name)
      subset_props.each{ |prop| validation.send("#{prop.to_s}=".to_sym, subset[prop]) } if subset 
    end
  end
  
  def init_validation_from_cv_statistics( validation, cv_uri, filter_params )
    
    bad_request_error "not a crossvalidation uri: "+cv_uri.to_s unless cv_uri =~ /crossvalidation.*\/[0-9]+$/
    
    if same_service?cv_uri
      cv_id = cv_uri.split("/")[-1]
      unauthorized_error "Not authorized: GET "+cv_uri.to_s if
        $aa[:uri] and !OpenTox::Authorization.authorized?(cv_uri,"GET")
      Ohm.connect(:thread_safe => true, :port => 6379)
      cv = Validation::Crossvalidation[cv_id]
      resource_not_found_error "crossvalidation with id "+crossvalidation_id.to_s+" not found" unless cv
      bad_request_error "crossvalidation with id "+crossvalidation_id.to_s+" is not finished yet" unless cv.finished
      v = Validation::Validation.from_cv_statistics(cv_id)
    else
      cv = YAML::load(OpenTox::RestClientWrapper.get cv_uri,nil,{:accept=>"application/serialize"})
      v = YAML::load(OpenTox::RestClientWrapper.get cv_uri+"/statistics",nil,{:accept=>"application/serialize"})
    end
    v.filter_predictions(filter_params[:min_confidence], filter_params[:min_num_predictions], filter_params[:max_num_predictions]) if 
      filter_params
    
    (Validation::VAL_PROPS + Validation::VAL_CV_PROPS).each do |p|
      validation.send("#{p.to_s}=".to_sym, v.send(p))
    end
    {:classification_statistics => Validation::VAL_CLASS_PROPS, 
     :regression_statistics => Validation::VAL_REGR_PROPS}.each do |subset_name,subset_props|
      subset = v.send(subset_name)
      subset_props.each{ |prop| validation.send("#{prop.to_s}=".to_sym, subset[prop]) } if subset
    end
    #cv props
    Validation::CROSS_VAL_PROPS.each do |p|
      validation.send("#{p.to_s}=".to_sym, cv.send(p.to_s))
    end
    validation.crossvalidation_uri = cv_uri
    validation.validation_uri = cv_uri+"/statistics"
  end
    
  def init_cv(validation)
    
    cv = nil
    if same_service?validation.crossvalidation_uri
      Ohm.connect(:thread_safe => true, :port => 6379)
      cv = Validation::Crossvalidation[validation.crossvalidation_id]
      bad_request_error "no crossvalidation found with id "+validation.crossvalidation_id.to_s unless cv
    else
      cv = YAML::load(OpenTox::RestClientWrapper.get validation.crossvalidation_uri,nil,{:accept=>"application/serialize"})
    end
    Validation::CROSS_VAL_PROPS.each do |p|
      validation.send("#{p.to_s}=".to_sym, cv.send(p.to_s))
    end
  end
  
  def training_feature_dataset_uri(validation)
    m = OpenTox::Model::Generic.find(validation.model_uri)
    if m
      f = m.metadata[RDF::OT.featureDataset]
      return f.chomp if f
    end
    internal_server_error "no feature dataset found"
  end

  def test_feature_dataset_uri(validation)
    training_features = Lib::DatasetCache.find( training_feature_dataset_uri(validation))
    test_dataset = Lib::DatasetCache.find( validation.test_dataset_uri)
    features_found = true 
    training_features.features.each do |f|
      unless test_dataset.features.include?(f)
      #unless test_dataset.find_feature_uri(f.uri)
        features_found = false
        $logger.debug "training-feature are not in test-datset #{f}"
        break
      end
    end
    if features_found
      $logger.debug "all training-features found in test-datset"
      uri = test_dataset.uri
    else
      m = OpenTox::Model::Generic.find(validation.model_uri)
      feat_gen = nil
      m.metadata[RDF::OT.parameters].each do |h|
        if h[RDF::DC.title] and h[RDF::DC.title]=~/feature_generation/ and h[RDF::OT.paramValue]
          feat_gen = h[RDF::OT.paramValue]
          break
        end
      end if m  and m.metadata[RDF::OT.parameters]
      internal_server_error "no feature creation alg found" unless feat_gen
      feat_gen = File.join(feat_gen,"match") if feat_gen=~/fminer/
      uri = OpenTox::RestClientWrapper.post(feat_gen,{
        :feature_dataset_uri=>training_feature_dataset_uri(validation),
        :dataset_uri=>validation.test_dataset_uri})
      @@tmp_resources << wait_for_task(uri)
    end
    uri
  end
  
  def delete_tmp_resources
    @@tmp_resources.each do |uri|
      OpenTox::RestClientWrapper.delete uri
    end
    @@tmp_resources = []
  end
    
  def get_predictions(validation, filter_params, task)
    # we need compound info, cannot reuse stored prediction data
    data = Lib::PredictionData.create( validation.feature_type, validation.test_dataset_uri, 
      validation.prediction_feature, validation.prediction_dataset_uri, validation.predicted_variable, 
      validation.predicted_confidence, OpenTox::SubTask.create(task, 0, 40 ) )
    data = Lib::PredictionData.filter_data( data.data, data.compounds, 
      filter_params[:min_confidence], filter_params[:min_num_predictions], filter_params[:max_num_predictions] ) if filter_params!=nil
	task.progress(80) if task
    training_values = {}
    if validation.training_dataset_uri
      d = Lib::DatasetCache.find(validation.training_dataset_uri)
      data.compounds.each do |c|
        training_values[c] = (d.compound_indices(c) ? d.compound_indices(c).collect{|idx| d.data_entry_value(idx,validation.prediction_feature)} : nil)
      end
    end
    task.progress(90) if task
    Lib::OTPredictions.new( data.data, data.compounds, training_values )
  end
  
  def get_accept_values( validation )
    # PENDING So far, one has to load the whole dataset to get the accept_value from ambit
    test_datasets = validation.test_dataset_uri
    res = nil
    test_datasets.split(";").each do |test_dataset|
      d = Lib::DatasetCache.find( test_dataset)
      internal_server_error "cannot get test target dataset for accept values, dataset: "+test_dataset.to_s unless d
      feature = OpenTox::Feature.find(validation.prediction_feature)
      accept_values = feature.accept_values
      internal_server_error "cannot get accept values for feature "+
        validation.prediction_feature+":\n"+feature.to_yaml unless accept_values!=nil
      internal_server_error "different accept values" if res && res!=accept_values
      res = accept_values
    end
    res
  end
  
  def feature_type( validation )
    m = OpenTox::Model::Generic.new(validation.model_uri)
    #m.get
    m.feature_type
    #get_model(validation).classification?
  end
  
  def predicted_variable(validation)
    internal_server_error "cannot derive model depended props for merged validations" if Lib::MergeObjects.merged?(validation)
    model = OpenTox::Model::Generic.new(validation.model_uri)
    model.get
    resource_not_found_error "model not found '"+validation.model_uri+"'" unless model
    model.predicted_variable
  end
  
  def predicted_confidence(validation)
    internal_server_error "cannot derive model depended props for merged validations" if Lib::MergeObjects.merged?(validation)
    model = OpenTox::Model::Generic.new(validation.model_uri)
    model.get
    resource_not_found_error "model not found '"+validation.model_uri+"'" unless model
    model.predicted_confidence
  end
  
#  private
#  def get_model(validation)
#    internal_server_error "cannot derive model depended props for merged validations" if Lib::MergeObjects.merged?(validation)
#    model = @model_store[validation.model_uri]
#    unless model
#      model = OpenTox::Model::PredictionModel.find(validation.model_uri)
#      internal_server_error "model not found '"+validation.model_uri+"'" unless validation.model_uri && model
#      @model_store[validation.model_uri] = model
#    end
#    return model
#  end
  
end
