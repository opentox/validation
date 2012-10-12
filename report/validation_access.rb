require "lib/validation_db.rb"

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
  
  def resolve_cv_uris(validation_uris, identifier, subjectid)
    res = {}
    count = 0
    validation_uris.each do |u|
      
      if u.to_s =~ /.*\/crossvalidation\/[0-9]+/
        cv = nil
        cv_id = u.split("/")[-1].to_i
        val_uris = nil
        
        if same_service?u
          raise OpenTox::NotAuthorizedError.new "Not authorized: GET "+u.to_s if
            AA_SERVER and !OpenTox::Authorization.authorized?(u,"GET",subjectid)
          cv = Validation::Crossvalidation.get( cv_id )
                  raise OpenTox::NotFoundError.new "crossvalidation with id "+cv_id.to_s+" not found" unless cv
          raise OpenTox::BadRequestError.new("crossvalidation with id '"+cv_id.to_s+"' not finished") unless cv.finished
          #res += Validation::Validation.find( :all, :conditions => { :crossvalidation_id => cv_id } ).collect{|v| v.validation_uri.to_s}
          val_uris = Validation::Validation.find( :crossvalidation_id => cv_id, :validation_type => "crossvalidation" ).collect{|v| v.validation_uri.to_s}
        else
          val_base_uri = u.gsub(/\/crossvalidation\/[0-9]+/,"")
          val_uris = OpenTox::RestClientWrapper.get( val_base_uri+"?crossvalidation_id="+cv_id.to_s+"&validation_type=crossvalidation", {:subjectid => subjectid, :accept => "text/uri-list" }).split("\n")
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
  
  def init_validation(validation, uri, filter_params, subjectid)
    
    raise OpenTox::BadRequestError.new "not a validation uri: "+uri.to_s unless uri =~ /\/[0-9]+$/
    validation_id = uri.split("/")[-1]
    raise OpenTox::BadRequestError.new "invalid validation id "+validation_id.to_s unless validation_id!=nil and 
      (validation_id.to_i > 0 || validation_id.to_s=="0" )
     
    v = nil
    
    if same_service? uri
      raise OpenTox::NotAuthorizedError.new "Not authorized: GET "+uri.to_s if
        AA_SERVER and !OpenTox::Authorization.authorized?(uri,"GET",subjectid)
      v = Validation::Validation.get(validation_id)
    else
      v = YAML::load(OpenTox::RestClientWrapper.get uri, {:subjectid=>subjectid, :accept=>"application/serialize"})
    end
    v.subjectid = subjectid
    v.filter_predictions(filter_params[:min_confidence], filter_params[:min_num_predictions], filter_params[:max_num_predictions]) if 
      filter_params
    
    raise OpenTox::NotFoundError.new "validation with id "+validation_id.to_s+" not found" unless v
    raise OpenTox::BadRequestError.new "validation with id "+validation_id.to_s+" is not finished yet" unless v.finished
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
  
  def init_validation_from_cv_statistics( validation, cv_uri, filter_params, subjectid )
    
    raise OpenTox::BadRequestError.new "not a crossvalidation uri: "+cv_uri.to_s unless cv_uri.uri? and cv_uri =~ /crossvalidation.*\/[0-9]+$/
    
    if same_service?cv_uri
      cv_id = cv_uri.split("/")[-1]
      raise OpenTox::NotAuthorizedError.new "Not authorized: GET "+cv_uri.to_s if
        AA_SERVER and !OpenTox::Authorization.authorized?(cv_uri,"GET",subjectid)
      cv = Validation::Crossvalidation.get(cv_id)
      raise OpenTox::NotFoundError.new "crossvalidation with id "+crossvalidation_id.to_s+" not found" unless cv
      raise OpenTox::BadRequestError.new "crossvalidation with id "+crossvalidation_id.to_s+" is not finished yet" unless cv.finished
      v = Validation::Validation.from_cv_statistics(cv_id, subjectid)
    else
      cv = YAML::load(OpenTox::RestClientWrapper.get cv_uri, {:subjectid=>subjectid, :accept=>"application/serialize"})
      v = YAML::load(OpenTox::RestClientWrapper.get cv_uri+"/statistics", {:subjectid=>subjectid, :accept=>"application/serialize"})
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
    
  def init_cv(validation, subjectid)
    
    cv = nil
    if same_service?validation.crossvalidation_uri
      cv = Validation::Crossvalidation.get(validation.crossvalidation_id)
      raise OpenTox::BadRequestError.new "no crossvalidation found with id "+validation.crossvalidation_id.to_s unless cv
    else
      cv = YAML::load(OpenTox::RestClientWrapper.get validation.crossvalidation_uri, {:subjectid=>subjectid, :accept=>"application/serialize"})
    end
    Validation::CROSS_VAL_PROPS.each do |p|
      validation.send("#{p.to_s}=".to_sym, cv.send(p.to_s))
    end
  end
  
  def training_feature_dataset_uri(validation, subjectid)
    m = OpenTox::Model::Generic.find(validation.model_uri, subjectid)
    if m
      f = m.metadata[OT.featureDataset]
      return f.chomp if f
    end
    raise "no feature dataset found"
  end

  def test_feature_dataset_uri(validation, subjectid)
    training_features = Lib::DatasetCache.find( training_feature_dataset_uri(validation,subjectid), subjectid )
    test_dataset = Lib::DatasetCache.find( validation.test_dataset_uri, subjectid )
    features_found = true 
    training_features.features.keys.each do |f|
      unless test_dataset.features.keys.include?(f)
        features_found = false
        LOGGER.debug "training-feature are not in test-datset #{f}"
        break
      end
    end
    if features_found
      LOGGER.debug "all training-features found in test-datset"
      uri = test_dataset.uri
    elsif validation.model_uri=~/superservice/
      uri = OpenTox::RestClientWrapper.post(validation.model_uri+"/test_dataset_features",
        {:dataset_uri=>validation.test_dataset_uri}).to_s
    else
      m = OpenTox::Model::Generic.find(validation.model_uri, subjectid)
      feat_gen = nil
      m.metadata[OT.parameters].each do |h|
        if h[DC.title] and h[DC.title]=~/feature_generation/ and h[OT.paramValue]
          feat_gen = h[OT.paramValue]
          break
        end
      end if m  and m.metadata[OT.parameters]
      raise "no feature creation alg found" unless feat_gen
      feat_gen = File.join(feat_gen,"match") if feat_gen=~/fminer/
      uri = OpenTox::RestClientWrapper.post(feat_gen,{:subjectid => subjectid,
        :feature_dataset_uri=>training_feature_dataset_uri(validation,subjectid),
        :dataset_uri=>validation.test_dataset_uri})
      @@tmp_resources << uri
    end
    uri
  end
  
  def delete_tmp_resources(subjectid)
    @@tmp_resources.each do |uri|
      OpenTox::RestClientWrapper.delete uri,{:subjectid=>subjectid}
    end
    @@tmp_resources = []
  end
    
  def get_predictions(validation, filter_params, subjectid, task)
    # we need compound info, cannot reuse stored prediction data
    data = Lib::PredictionData.create( validation.feature_type, validation.test_dataset_uri, 
      validation.test_target_dataset_uri, validation.prediction_feature, validation.prediction_dataset_uri, 
      validation.predicted_variable, validation.predicted_confidence, subjectid, OpenTox::SubTask.create(task, 0, 80 ) )
    data = Lib::PredictionData.filter_data( data.data, data.compounds, 
      filter_params[:min_confidence], filter_params[:min_num_predictions], filter_params[:max_num_predictions] ) if filter_params!=nil
    task.progress(100) if task
    Lib::OTPredictions.new( data.data, data.compounds )
  end
  
  @@accept_values = {}
  
  def get_accept_values( validation, subjectid=nil )
    begin
      return @@accept_values[validation.prediction_feature] if @@accept_values[validation.prediction_feature]
      LOGGER.debug "get accept values ..."
      pred = OpenTox::Feature.find(validation.prediction_feature)
      accept = pred.metadata[OT.acceptValue]
      accept = accept[0] if accept.is_a?(Array) and accept.size==1 and accept[0].is_a?(Array)
      raise unless accept.is_a?(Array) and accept.size>1
      @@accept_values[validation.prediction_feature] = accept
      LOGGER.debug "get accept values ... #{accept} #{accept.size}"
      accept
    rescue
      # PENDING So far, one has to load the whole dataset to get the accept_value from ambit
      test_target_datasets = validation.test_target_dataset_uri
      test_target_datasets = validation.test_dataset_uri unless test_target_datasets
      res = nil
      test_target_datasets.split(";").each do |test_target_dataset|
        d = Lib::DatasetCache.find( test_target_dataset, subjectid )
        raise "cannot get test target dataset for accept values, dataset: "+test_target_dataset.to_s unless d
        accept_values = d.accept_values(validation.prediction_feature)
        raise "cannot get accept values from dataset "+test_target_dataset.to_s+" for feature "+
          validation.prediction_feature+":\n"+d.features[validation.prediction_feature].to_yaml unless accept_values!=nil
        raise "different accept values" if res && res!=accept_values
        res = accept_values
      end
      res
    end
  end
  
  def feature_type( validation, subjectid=nil )
    if validation.model_uri.include?(";")
      model_uri = validation.model_uri.split(";")[0]
    else
      model_uri = validation.model_uri
    end 
    OpenTox::Model::Generic.new(model_uri).feature_type(subjectid)
    #get_model(validation).classification?
  end
  
  def predicted_variable(validation, subjectid=nil)
    raise "cannot derive model depended props for merged validations" if Lib::MergeObjects.merged?(validation)
    raise "multiple models in this validation, cannot get one predicted variable (#{validation.model_uri})" if validation.model_uri.include?(";")
    model = OpenTox::Model::Generic.find(validation.model_uri, subjectid)
    raise OpenTox::NotFoundError.new "model not found '"+validation.model_uri+"'" unless model
    model.predicted_variable(subjectid)
  end
  
  def predicted_confidence(validation, subjectid=nil)
    raise "cannot derive model depended props for merged validations" if Lib::MergeObjects.merged?(validation)
    raise "multiple models in this validation, cannot get one predicted confidence (#{validation.model_uri})" if validation.model_uri.include?(";")
    model = OpenTox::Model::Generic.find(validation.model_uri, subjectid)
    raise OpenTox::NotFoundError.new "model not found '"+validation.model_uri+"'" unless model
    model.predicted_confidence(subjectid)
  end
  
#  private
#  def get_model(validation)
#    raise "cannot derive model depended props for merged validations" if Lib::MergeObjects.merged?(validation)
#    model = @model_store[validation.model_uri]
#    unless model
#      model = OpenTox::Model::PredictionModel.find(validation.model_uri)
#      raise "model not found '"+validation.model_uri+"'" unless validation.model_uri && model
#      @model_store[validation.model_uri] = model
#    end
#    return model
#  end
  
end
