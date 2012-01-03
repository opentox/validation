require "lib/validation_db.rb"

# = Reports::ValidationDB
# 
# connects directly to the validation db, overwirte with restclient calls 
# if reports/reach reports are seperated from validation someday
#  
class Reports::ValidationDB
  
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

  def get_predictions(validation, filter_params, subjectid, task)
    # we need compound info, cannot reuse stored prediction data
    data = Lib::PredictionData.create( validation.feature_type, validation.test_dataset_uri, 
      validation.test_target_dataset_uri, validation.prediction_feature, validation.prediction_dataset_uri, 
      validation.predicted_variable, validation.predicted_confidence, subjectid, task )
    data = Lib::PredictionData.filter_data( data.data, data.compounds, 
      filter_params[:min_confidence], filter_params[:min_num_predictions], filter_params[:max_num_predictions] ) if filter_params!=nil
    Lib::OTPredictions.new( data.data, data.compounds )
  end
  
  def get_accept_values( validation, subjectid=nil )
    # PENDING So far, one has to load the whole dataset to get the accept_value from ambit
    test_target_dataset = validation.test_target_dataset_uri
    test_target_dataset = validation.test_dataset_uri unless test_target_dataset
    d = Lib::DatasetCache.find( test_target_dataset, subjectid )
    raise "cannot get test target dataset for accept values, dataset: "+test_target_dataset.to_s unless d
    accept_values = d.accept_values(validation.prediction_feature)
    raise "cannot get accept values from dataset "+test_target_dataset.to_s+" for feature "+
      validation.prediction_feature+":\n"+d.features[validation.prediction_feature].to_yaml unless accept_values!=nil
    accept_values
  end
  
  def feature_type( validation, subjectid=nil )
    OpenTox::Model::Generic.new(validation.model_uri).feature_type(subjectid)
    #get_model(validation).classification?
  end
  
  def predicted_variable(validation, subjectid=nil)
    raise "cannot derive model depended props for merged validations" if Lib::MergeObjects.merged?(validation)
    model = OpenTox::Model::Generic.find(validation.model_uri, subjectid)
    raise OpenTox::NotFoundError.new "model not found '"+validation.model_uri+"'" unless model
    model.predicted_variable(subjectid)
  end
  
  def predicted_confidence(validation, subjectid=nil)
    raise "cannot derive model depended props for merged validations" if Lib::MergeObjects.merged?(validation)
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
