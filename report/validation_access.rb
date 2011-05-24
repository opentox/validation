require "lib/validation_db.rb"

# = Reports::ValidationDB
# 
# connects directly to the validation db, overwirte with restclient calls 
# if reports/reach reports are seperated from validation someday
#  
class Reports::ValidationDB
  
  def resolve_cv_uris(validation_uris, identifier=nil, subjectid=nil)
    res = {}
    count = 0
    validation_uris.each do |u|
      if u.to_s =~ /.*\/crossvalidation\/[0-9]+/
        cv_id = u.split("/")[-1].to_i
        cv = nil
        
        raise OpenTox::NotAuthorizedError.new "Not authorized: GET "+u.to_s if
          AA_SERVER and !OpenTox::Authorization.authorized?(u,"GET",subjectid)
#        begin
#          #cv = Lib::Crossvalidation.find( cv_id )
#        rescue => ex
#          raise "could not access crossvalidation with id "+validation_id.to_s+", error-msg: "+ex.message
#        end
        cv = Validation::Crossvalidation.get( cv_id )
        raise OpenTox::NotFoundError.new "crossvalidation with id "+cv_id.to_s+" not found" unless cv
        raise OpenTox::BadRequestError.new("crossvalidation with id '"+cv_id.to_s+"' not finished") unless cv.finished
        #res += Validation::Validation.find( :all, :conditions => { :crossvalidation_id => cv_id } ).collect{|v| v.validation_uri.to_s}
        Validation::Validation.find( :crossvalidation_id => cv_id, :validation_type => "crossvalidation" ).each do |v|
          res[v.validation_uri.to_s] = identifier ? identifier[count] : nil
        end
      else
        res[u.to_s] = identifier ? identifier[count] : nil
      end
      count += 1
    end
    res
  end
  
  def init_validation(validation, uri, subjectid=nil)
  
    raise OpenTox::BadRequestError.new "not a validation uri: "+uri.to_s unless uri =~ /\/[0-9]+$/
    validation_id = uri.split("/")[-1]
    raise OpenTox::BadRequestError.new "invalid validation id "+validation_id.to_s unless validation_id!=nil and 
      (validation_id.to_i > 0 || validation_id.to_s=="0" )
    v = nil
    raise OpenTox::NotAuthorizedError.new "Not authorized: GET "+uri.to_s if
      AA_SERVER and !OpenTox::Authorization.authorized?(uri,"GET",subjectid)
    v = Validation::Validation.get(validation_id)
    raise OpenTox::NotFoundError.new "validation with id "+validation_id.to_s+" not found" unless v
    raise OpenTox::BadRequestError.new "validation with id "+validation_id.to_s+" is not finished yet" unless v.finished
    
    (Validation::VAL_PROPS + Validation::VAL_CV_PROPS).each do |p|
      validation.send("#{p.to_s}=".to_sym, v.send(p))
    end
    
    {:classification_statistics => Validation::VAL_CLASS_PROPS, 
     :regression_statistics => Validation::VAL_REGR_PROPS}.each do |subset_name,subset_props|
      subset = v.send(subset_name)
      subset_props.each{ |prop| validation.send("#{prop.to_s}=".to_sym, subset[prop]) } if subset
    end
  end
  
  def init_validation_from_cv_statistics( validation, cv_uri, subjectid=nil )
    
    raise OpenTox::BadRequestError.new "not a crossvalidation uri: "+cv_uri.to_s unless cv_uri.uri? and cv_uri =~ /crossvalidation.*\/[0-9]+$/
    cv_id = cv_uri.split("/")[-1]
    raise OpenTox::NotAuthorizedError.new "Not authorized: GET "+cv_uri.to_s if
      AA_SERVER and !OpenTox::Authorization.authorized?(cv_uri,"GET",subjectid)
    cv = Validation::Crossvalidation.get(cv_id)
    raise OpenTox::NotFoundError.new "crossvalidation with id "+crossvalidation_id.to_s+" not found" unless cv
    raise OpenTox::BadRequestError.new "crossvalidation with id "+crossvalidation_id.to_s+" is not finished yet" unless cv.finished
    v = Validation::Validation.from_cv_statistics(cv_id, subjectid)
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
  end
    
  def init_cv(validation)
    
    #cv = Lib::Crossvalidation.find(validation.crossvalidation_id)
    cv = Validation::Crossvalidation.get(validation.crossvalidation_id)
    raise OpenTox::BadRequestError.new "no crossvalidation found with id "+validation.crossvalidation_id.to_s unless cv
    
    Validation::CROSS_VAL_PROPS.each do |p|
      validation.send("#{p.to_s}=".to_sym, cv.send(p.to_s))        
    end
  end

  def get_predictions(validation, subjectid=nil, task=nil)
    Lib::OTPredictions.new( validation.feature_type, validation.test_dataset_uri, 
      validation.test_target_dataset_uri, validation.prediction_feature, validation.prediction_dataset_uri, 
      validation.predicted_variable, validation.predicted_confidence, subjectid, task)
  end
  
  def get_accept_values( validation, subjectid=nil )
    # PENDING So far, one has to load the whole dataset to get the accept_value from ambit
    test_target_dataset = validation.test_target_dataset_uri
    test_target_dataset = validation.test_dataset_uri unless test_target_dataset
    d = Lib::DatasetCache.find( test_target_dataset, subjectid )
    raise "cannot get test target dataset for accept values, dataset: "+test_target_dataset.to_s unless d
    accept_values = d.features[validation.prediction_feature][OT.acceptValue]
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
    Lib::FeatureUtil.predicted_variables(model, validation.prediction_dataset_uri, subjectid)[:predicted_variable]
  end
  
  def predicted_confidence(validation, subjectid=nil)
    raise "cannot derive model depended props for merged validations" if Lib::MergeObjects.merged?(validation)
    model = OpenTox::Model::Generic.find(validation.model_uri, subjectid)
    raise OpenTox::NotFoundError.new "model not found '"+validation.model_uri+"'" unless model
    Lib::FeatureUtil.predicted_variables(model, validation.prediction_dataset_uri, subjectid)[:predicted_confidence]
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
